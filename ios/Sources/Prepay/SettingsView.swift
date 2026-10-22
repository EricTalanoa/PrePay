import PrepayCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var raiseRate = 0.0
    @State private var raiseNext = true
    @State private var customStart = false

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
                              value: cur?.rate ?? 0) { model.setBaseRate($0) }
                } header: { Text("Hourly rate") }

                Section {
                    if let pending {
                        HStack {
                            Text("$\(f2(pending.rate)) from \(fmtMD(pending.effectiveFrom)) onward").foregroundStyle(Theme.accent)
                            Spacer()
                            Button("Clear") { model.clearRaise() }
                        }
                    } else {
                        HStack {
                            Text("New rate")
                            Spacer()
                            DecimalField(placeholder: "0.00", value: $raiseRate)
                        }
                        Picker("Starts", selection: $raiseNext) {
                            Text("This period · \(fmtMD(pay.from))").tag(false)
                            Text("Next · \(fmtMD(nextPeriod(pay).from))").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Button("Start the raise") {
                            model.scheduleRaise(raiseRate, from: raiseNext ? nextPeriod(pay).from : pay.from)
                            raiseRate = 0
                        }
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
                        DatePicker("Clock in at", selection: minutesBinding({ model.data.settings.defaultStartMin },
                                                                            { v in model.updateSettings { $0.defaultStartMin = v } }),
                                   displayedComponents: .hourAndMinute)
                    }
                    Toggle("Lunch taken by default", isOn: Binding(
                        get: { s.defaultLunch }, set: { v in model.updateSettings { $0.defaultLunch = v } }))
                }

                Section {
                    Toggle("Tuition reimbursement", isOn: Binding(
                        get: { s.tuitionOn }, set: { v in model.updateSettings { $0.tuitionOn = v } }))
                    if s.tuitionOn {
                        StubField(title: "Per hour worked", note: tuitionNote(data, pay, today), value: s.tuitionRate) { v in
                            model.updateSettings { $0.tuitionRate = v }
                        }
                    }
                } footer: {
                    Text("Usually every other check. If an expected one doesn't come, it moves to the next check — Pay day asks after each one.")
                }

                Section("POV mileage") {
                    StubField(title: "Per mile", note: "reimbursed, not taxed", value: s.mileRate) { v in
                        model.updateSettings { $0.mileRate = v }
                    }
                }

                Section {
                    StubField(title: "Available", note: "type the balance off your latest stub", value: cents(ledger.available)) {
                        model.setSickAvailable($0)
                    }
                    StubField(title: "Cash out on the \(fmtMD(pay.payDate)) check", note: "\(f2(ledger.available + cashout)) h can be cashed",
                              value: cashout) { model.setCashout(pay.key, hours: max(0, $0)) }
                    if ledger.available < -1e-9 {
                        Text("More than you have accrued").foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Sick hours")
                } footer: {
                    Text((cashout > 0 ? "\(money(e.totals.sickPay)) on the \(fmtMD(pay.payDate)) check, already off your balance. " : "")
                         + "+\(f2(e.accrual)) h accruing this period, credited \(fmtMD(pay.payDate)).")
                }

                Section("Account") {
                    Text(model.email).font(Theme.mono(13))
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
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
