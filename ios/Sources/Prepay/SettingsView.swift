import PrepayCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var raiseRate = 0.0
    @State private var raiseNext = true
    @State private var customStart = false
    @AppStorage(ThemeChoice.key) private var theme = ThemeChoice.classic.rawValue

    private static let presets = [465, 480]

    var body: some View {
        let data = model.data
        let s = data.settings
        let today = todayIso()
        let pay = upcomingPeriod()
        let cur = currentRate(data.rates, today)
        let pending = pendingRaise(data.rates, today)
        let ledger = sickLedger(data, today)
        let cashout = data.cashouts.first { $0.periodStart == pay.key }?.hours ?? 0
        let e = estimate(data, pay, today)

        NavigationStack {
            Form {
                Section {
                    StubField(title: "Base rate", note: cur.map { "OT $\(f2($0.rate * OT_MULT))" } ?? "what you make an hour",
                              icon: "dollarsign.circle", value: cur?.rate ?? 0) { model.setBaseRate($0) }
                } header: { Text("Hourly rate") }

                Section {
                    if let pending {
                        HStack {
                            Label("$\(f2(pending.rate)) from \(fmtMD(pending.effectiveFrom)) onward", systemImage: "arrow.up.right.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button("Clear") { model.clearRaise() }
                        }
                    } else {
                        HStack {
                            Label("New rate", systemImage: "arrow.up.right.circle")
                            Spacer()
                            DecimalField(placeholder: "0.00", value: $raiseRate)
                        }
                        Picker("Starts", selection: $raiseNext) {
                            Text("This period · \(fmtMD(pay.from))").tag(false)
                            Text("Next · \(fmtMD(nextPeriod(pay).from))").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Button {
                            model.scheduleRaise(raiseRate, from: raiseNext ? nextPeriod(pay).from : pay.from)
                            raiseRate = 0
                        } label: { Label("Start the raise", systemImage: "checkmark.circle.fill").fontWeight(.semibold) }
                        .disabled(raiseRate <= 0)
                    }
                } header: { Text("Raise") } footer: { Text("Once its date arrives it becomes the base rate.") }

                Section("Work day defaults") {
                    Picker("Start time", selection: Binding(
                        get: { customStart || !Self.presets.contains(s.defaultStartMin) ? -1 : s.defaultStartMin },
                        set: { v in
                            customStart = v == -1
                            if v != -1 { model.updateSettings { $0.defaultStartMin = v } }
                        }
                    )) {
                        ForEach(Self.presets, id: \.self) { Text(fmtTime($0)).tag($0) }
                        Text("Custom").tag(-1)
                    }
                    .pickerStyle(.segmented)
                    if customStart || !Self.presets.contains(s.defaultStartMin) {
                        DatePicker(selection: minutesBinding({ model.data.settings.defaultStartMin },
                                                                            { v in model.updateSettings { $0.defaultStartMin = v } }),
                                   displayedComponents: .hourAndMinute) { Label("Clock in at", systemImage: "clock") }
                    }
                    Toggle(isOn: Binding(
                        get: { s.defaultLunch }, set: { v in model.updateSettings { $0.defaultLunch = v } })) {
                        Label("Lunch taken by default", systemImage: "fork.knife")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { s.tuitionOn }, set: { v in model.updateSettings { $0.tuitionOn = v } })) {
                        Label("Tuition reimbursement", systemImage: "graduationcap")
                    }
                    if s.tuitionOn {
                        StubField(title: "Per hour worked", note: tuitionNote(data, pay, today), icon: "clock.badge.checkmark", value: s.tuitionRate) { v in
                            model.updateSettings { $0.tuitionRate = v }
                        }
                    }
                } footer: {
                    Text("Usually every other check. If an expected one doesn't come, it moves to the next check — Pay day asks after each one.")
                }

                Section("POV mileage") {
                    StubField(title: "Per mile", note: "reimbursed, not taxed", icon: "car", value: s.mileRate) { v in
                        model.updateSettings { $0.mileRate = v }
                    }
                }

                Section {
                    StubField(title: "Available", note: "type the balance off your latest stub", icon: "cross.case", value: cents(ledger.available)) {
                        model.setSickAvailable($0)
                    }
                    StubField(title: "Cash out on the \(fmtMD(pay.payDate)) check", note: "\(f2(ledger.available + cashout)) h can be cashed",
                              icon: "banknote", value: cashout) { model.setCashout(pay.key, hours: max(0, $0)) }
                    if ledger.available < -1e-9 {
                        Label("More than you have accrued", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Sick hours")
                } footer: {
                    Text((cashout > 0 ? "\(money(e.totals.sickPay)) on the \(fmtMD(pay.payDate)) check, already off your balance. " : "")
                         + "+\(f2(e.accrual)) h accruing this period, credited \(fmtMD(pay.payDate)).")
                }

                Section {
                    HStack(spacing: 12) {
                        ForEach(ThemeChoice.allCases) { t in
                            ThemeSwatch(choice: t, selected: theme == t.rawValue) {
                                withAnimation(.snappy) { theme = t.rawValue }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: { Text("Theme") } footer: { Text("Saved on this phone.") }

                Section("Account") {
                    HStack(spacing: 12) {
                        Text(String(model.email.prefix(1)).uppercased())
                            .font(Theme.serif(20, weight: .semibold)).foregroundStyle(Theme.onButton)
                            .frame(width: 40, height: 40)
                            .background(Theme.button, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in").font(.caption).foregroundStyle(Theme.muted)
                            Text(model.email).font(Theme.mono(13)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 2)
                    Button(role: .destructive) { Task { await model.signOut() } } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Settings")
        }
    }

    private func tuitionNote(_ data: PrepayData, _ pay: Period, _ today: ISODate) -> String {
        var p = pay
        for _ in 0..<6 {
            if tuitionExpected(data, p, today) {
                return "next on \(fmtMD(p.payDate)) · about \(money(tuitionOwed(data, p).amount))"
            }
            p = nextPeriod(p)
        }
        return "not expected soon"
    }
}

/// A small preview of a theme: its page, a hero card, and a button.
private struct ThemeSwatch: View {
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let p = choice.palette
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(p.hero)
                        .overlay(alignment: .leading) {
                            Text("$204").font(Theme.serif(15, weight: .semibold)).foregroundStyle(p.onHero).padding(.leading, 8)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(p.heroStroke))
                        .shadow(color: p.glow, radius: 6)
                        .frame(height: 34)
                    HStack(spacing: 4) {
                        Capsule().fill(p.ink.opacity(0.7)).frame(width: 34, height: 4)
                        Spacer()
                        Capsule().fill(p.accent).frame(width: 14, height: 4)
                    }
                    Capsule().fill(p.button).frame(height: 12)
                }
                .padding(10)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2.5 : 1))

                Label(choice.name, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(choice.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
