import Foundation
import Observation
import PrepayCore
import Supabase

// Holds the signed-in user's data and every change to it. Like the web app's
// store: a change lands in memory first so the screen never waits on the
// network, then goes to Supabase; a failed write reloads from the database.
@MainActor @Observable
final class AppModel {
    enum Phase { case starting, signedOut, loading, ready }
    enum Tab: Hashable { case day, pay, history, settings }

    var phase: Phase = .starting
    var data = PrepayData()
    var email = ""
    var error: String?

    var tab: Tab = .day
    var draft = Day(date: todayIso(), startMin: 465, endMin: 465, lunch: true)
    var editing = false

    let client = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseKey)

    // MARK: - session

    func start() async {
        for await (_, session) in client.auth.authStateChanges {
            if let session {
                email = session.user.email ?? ""
                if phase == .starting || phase == .signedOut { await load() }
            } else {
                data = PrepayData()
                phase = .signedOut
            }
        }
    }

    func signIn(_ provider: Provider) async {
        do {
            _ = try await client.auth.signInWithOAuth(provider: provider, redirectTo: Config.authRedirect)
        } catch {
            // closing the sheet is not an error worth showing
            if (error as NSError).domain != "com.apple.AuthenticationServices.WebAuthenticationSession" {
                self.error = error.localizedDescription
            }
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func load() async {
        if phase != .ready { phase = .loading }
        do {
            let days: [Day] = try await client.from("days").select().order("date").execute().value
            let stubs: [Stub] = try await client.from("stubs").select().order("period_start", ascending: false).execute().value
            let rates: [Rate] = try await client.from("rates").select("effective_from, rate").order("effective_from").execute().value
            let settings: [Settings] = try await client.from("settings").select().execute().value
            let cashouts: [Cashout] = try await client.from("sick_cashouts").select("period_start, hours").execute().value
            let tuition: [TuitionEvent] = try await client.from("tuition_events").select("period_start, status, amount").execute().value
            data = PrepayData(days: days, stubs: stubs, rates: rates, settings: settings.first ?? .defaults(),
                              cashouts: cashouts, tuition: tuition)
            if phase != .ready { resetDraft() }
            phase = .ready
        } catch {
            self.error = error.localizedDescription
            if phase != .ready { phase = .ready }
        }
    }

    private func write(_ op: @escaping @Sendable (SupabaseClient) async throws -> Void) {
        let client = client
        Task {
            do { try await op(client) } catch {
                self.error = error.localizedDescription
                await self.load()
            }
        }
    }

    // MARK: - work day draft

    /// Clocking out "now" before the shift's start would wrap the day round to
    /// ~22 hours, so hold at the start until the clock passes it.
    static func endNow(_ start: Int) -> Int { max(nowMinutes(), start) }

    func resetDraft() {
        let s = data.settings
        draft = Day(date: todayIso(), startMin: s.defaultStartMin, endMin: Self.endNow(s.defaultStartMin), lunch: s.defaultLunch)
        editing = false
    }

    func edit(_ d: Day) {
        draft = d
        editing = true
        tab = .day
    }

    // MARK: - changes

    func saveDraft() {
        let d = draft
        data.days.removeAll { $0.id == d.id }
        data.days.append(d)
        resetDraft()
        tab = .pay
        write { _ = try await $0.from("days").upsert(d, returning: .minimal).execute() }
    }

    func deleteDraft() {
        let id = draft.id
        data.days.removeAll { $0.id == id }
        resetDraft()
        write { _ = try await $0.from("days").delete().eq("id", value: id).execute() }
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        change(&data.settings)
        let s = data.settings
        write { _ = try await $0.from("settings").upsert(s, returning: .minimal).execute() }
    }

    private func saveRate(_ r: Rate) {
        data.rates.removeAll { $0.effectiveFrom == r.effectiveFrom }
        data.rates.append(r)
        write { _ = try await $0.from("rates").upsert(r, onConflict: "user_id,effective_from", returning: .minimal).execute() }
    }

    /// Editing the base rate edits whichever rate is in force today.
    func setBaseRate(_ rate: Double) {
        guard rate > 0 else { return }
        saveRate(Rate(effectiveFrom: currentRate(data.rates, todayIso())?.effectiveFrom ?? "2000-01-01", rate: rate))
    }

    func scheduleRaise(_ rate: Double, from: ISODate) {
        guard rate > 0 else { return }
        if let old = pendingRaise(data.rates, todayIso()), old.effectiveFrom != from { deleteRate(old) }
        saveRate(Rate(effectiveFrom: from, rate: rate))
    }

    func clearRaise() {
        if let old = pendingRaise(data.rates, todayIso()) { deleteRate(old) }
    }

    private func deleteRate(_ r: Rate) {
        data.rates.removeAll { $0.effectiveFrom == r.effectiveFrom }
        let from = r.effectiveFrom
        write { _ = try await $0.from("rates").delete().eq("effective_from", value: from).execute() }
    }

    func saveStub(_ s: Stub) {
        data.stubs.removeAll { $0.periodStart == s.periodStart }
        data.stubs.append(s)
        write { _ = try await $0.from("stubs").upsert(s, returning: .minimal).execute() }
    }

    func deleteStub(_ key: ISODate) {
        data.stubs.removeAll { $0.periodStart == key }
        write { _ = try await $0.from("stubs").delete().eq("period_start", value: key).execute() }
    }

    func setCashout(_ key: ISODate, hours: Double) {
        data.cashouts.removeAll { $0.periodStart == key }
        if hours > 0 {
            let c = Cashout(periodStart: key, hours: hours)
            data.cashouts.append(c)
            write { _ = try await $0.from("sick_cashouts").upsert(c, returning: .minimal).execute() }
        } else {
            write { _ = try await $0.from("sick_cashouts").delete().eq("period_start", value: key).execute() }
        }
    }

    /// The figure typed is "available right now", after any cash-out that is
    /// scheduled but not yet paid, so those are added back to the anchor.
    func setSickAvailable(_ hours: Double) {
        let today = todayIso()
        var at = data
        at.settings.sickBalance = 0
        at.settings.sickAsOf = today
        let pending = -sickLedger(at, today).available
        updateSettings { $0.sickBalance = hours + pending; $0.sickAsOf = today }
    }

    func setTuition(_ key: ISODate, _ status: TuitionEvent.Status?, amount: Double = 0) {
        data.tuition.removeAll { $0.periodStart == key }
        if let status {
            let e = TuitionEvent(periodStart: key, status: status, amount: amount)
            data.tuition.append(e)
            write { _ = try await $0.from("tuition_events").upsert(e, returning: .minimal).execute() }
        } else {
            write { _ = try await $0.from("tuition_events").delete().eq("period_start", value: key).execute() }
        }
    }
}
