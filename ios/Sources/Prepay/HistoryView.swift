import PrepayCore
import SwiftUI

private struct Entry: Identifiable {
    let period: Period
    let stub: Stub?
    var id: ISODate { period.key }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    private var entries: [Entry] {
        let pay = upcomingPeriod()
        var out: [ISODate: Entry] = [:]
        for s in model.data.stubs { out[s.periodStart] = Entry(period: periodOf(s.periodStart), stub: s) }
        for d in model.data.days {
            let p = periodOf(d.date)
            if out[p.key] == nil && p.to < pay.from { out[p.key] = Entry(period: p, stub: nil) }
        }
        return out.values.sorted { $0.id > $1.id }
    }

    var body: some View {
        let data = model.data
        let today = todayIso()
        let calc = computeHours(data.days)
        let prev = prevPeriod(upcomingPeriod())
        let havePrev = data.stubs.contains { $0.periodStart == prev.key }

        NavigationStack {
            List {
                if !havePrev {
                    Section {
                        Button { addStub(prev) } label: {
                            Label("Add the \(fmtMD(prev.payDate)) check", systemImage: "plus.circle.fill").fontWeight(.semibold)
                        }
                    } footer: {
                        Text("Prefilled from your log — type the real figures off the stub.")
                    }
                }
                if entries.isEmpty {
                    ContentUnavailableView("No past checks yet", systemImage: "tray",
                                           description: Text("Past periods appear once a pay day passes."))
                        .listRowBackground(Color.clear)
                }
                ForEach(entries) { e in
                    NavigationLink(value: e.period.key) {
                        let net = e.stub.map { stubTotals($0, rate: rateFor(data.rates, $0.periodStart)).net }
                            ?? estimate(data, e.period, today, calc).totals.net
                        HStack(spacing: 12) {
                            IconBadge(systemImage: e.stub == nil ? "doc.text.magnifyingglass" : "checkmark.seal.fill",
                                      color: e.stub == nil ? Theme.muted : Theme.accent, size: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Paid \(fmtMD(e.period.payDate))").fontWeight(.semibold)
                                    Pill(text: e.stub == nil ? "Estimate" : "Actual", color: e.stub == nil ? Theme.muted : Theme.accent)
                                }
                                Caps(fmtRange(e.period))
                            }
                            Spacer()
                            Text(money(net)).font(Theme.serif(21, weight: .semibold))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .paperBackground()
            .navigationTitle("History")
            .navigationDestination(for: ISODate.self) { key in PeriodDetailView(period: periodOf(key)) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { StatsView() } label: { Label("Stats", systemImage: "chart.bar.xaxis").labelStyle(.titleAndIcon) }
                }
            }
        }
    }

    private func addStub(_ p: Period) {
        let t = estimate(model.data, p, todayIso()).totals
        model.saveStub(Stub(periodStart: p.key, periodEnd: p.to, payDate: p.payDate,
                            regHours: cents(t.reg), otHours: cents(t.ot), ccTips: cents(t.tips), bonus: t.perDiem, sickHours: t.sick,
                            reimbursement: cents(t.tuition + t.milePay), tax: cents(t.tax), taxIsEstimate: true, cashTips: cents(t.cash)))
    }
}

struct PeriodDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let period: Period

    var body: some View {
        let data = model.data
        let calc = computeHours(data.days)
        let e = estimate(data, period, todayIso(), calc)
        let stub = data.stubs.first { $0.periodStart == period.key }
        let rate = rateFor(data.rates, period.from)

        Form {
            if let s = stub {
                let p = stubTotals(s, rate: rate)
                Section("Off the stub") {
                    StubField(title: "Regular hours", note: "@ $\(f2(rate))", value: s.regHours) { var x = s; x.regHours = $0; model.saveStub(x) }
                    StubField(title: "Overtime hours", note: "@ $\(f2(rate * OT_MULT))", value: s.otHours) { var x = s; x.otHours = $0; model.saveStub(x) }
                    StubField(title: "CC tips", note: "taxed as wages", value: s.ccTips) { var x = s; x.ccTips = $0; model.saveStub(x) }
                    StubField(title: "Per-diem", note: "printed as spot bonus", value: s.bonus) { var x = s; x.bonus = $0; model.saveStub(x) }
                    StubField(title: "Sick hours paid", note: "cashed out @ $\(f2(rate))", value: s.sickHours) { var x = s; x.sickHours = $0; model.saveStub(x) }
                    StubField(title: "Reimbursement", note: "tuition + mileage", value: s.reimbursement) { var x = s; x.reimbursement = $0; model.saveStub(x) }
                    StubField(title: "Taxes & deductions", note: s.taxIsEstimate ? "still the estimate — type it off the stub" : "as printed",
                              value: s.tax) { var x = s; x.tax = $0; x.taxIsEstimate = false; model.saveStub(x) }
                    StubField(title: "Cash tips", note: "off the check", value: s.cashTips) { var x = s; x.cashTips = $0; model.saveStub(x) }
                }
                Section {
                    LineRow(name: "Gross", amount: money(p.gross), bold: true)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Net pay").fontWeight(.semibold)
                        Spacer()
                        Text(money(p.net)).font(Theme.serif(26, weight: .semibold))
                    }
                    .padding(.vertical, 4)
                }
                let checks = mismatches(s, e.totals, hasDays: !e.list.isEmpty)
                if !checks.isEmpty {
                    Section {
                        ForEach(checks, id: \.self) { c in
                            Label { Text(c).font(Theme.mono(12)) } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    } header: { Text("Your log disagrees with this stub").foregroundStyle(Theme.accent) }
                }
            } else {
                let t = e.totals
                Section("Estimate") {
                    if t.reg > 0 { LineRow(name: "Regular \(f2(t.reg))h", amount: money(t.regPay)) }
                    if t.ot > 0 { LineRow(name: "Overtime \(f2(t.ot))h", amount: money(t.otPay)) }
                    if t.tips > 0 { LineRow(name: "CC tips", amount: money(t.tips)) }
                    if t.perDiem > 0 { LineRow(name: "Per-diem", amount: money(t.perDiem)) }
                    LineRow(name: "Gross", amount: money(t.gross), bold: true)
                    LineRow(name: "Est. taxes", amount: "−" + money(t.tax), dim: true)
                    if t.tuition > 0 { LineRow(name: "Tuition reimb.", amount: money(t.tuition)) }
                    if t.milePay > 0 { LineRow(name: "POV mileage", amount: money(t.milePay)) }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Net").fontWeight(.semibold)
                        Spacer()
                        Text(money(t.net)).font(Theme.serif(26, weight: .semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            if data.settings.tuitionOn {
                TuitionStatusSection(period: period)
            }

            if !e.list.isEmpty {
                Section("Logged days · tap to correct") {
                    ForEach(e.list.sorted { $0.date > $1.date }) { DayRowView(day: $0, calc: calc) }
                }
            }

            if stub != nil {
                Section {
                    Button("Remove stub", role: .destructive) { model.deleteStub(period.key); dismiss() }
                }
            }
        }
        .paperBackground()
        .navigationTitle("Paid \(fmtMD(period.payDate))")
        .navigationBarTitleDisplayMode(.inline)
    }

    // What the log says against what payroll paid: this is what turns up a
    // shift whose tips never made it onto the check.
    private func mismatches(_ s: Stub, _ l: Totals, hasDays: Bool) -> [String] {
        guard hasDays else { return [] }
        var out: [String] = []
        let word = { (x: Double) in x > 0 ? "SHORT" : "OVER" }
        let dT = l.tips - s.ccTips, dH = l.hrs - (s.regHours + s.otHours), dP = l.perDiem - s.bonus
        if abs(dT) > 0.005 { out.append("CC tips \(word(dT)) \(money(abs(dT))) · \(money(l.tips)) logged, \(money(s.ccTips)) paid") }
        if abs(dH) > 0.05 { out.append("Hours \(word(dH)) \(f2(abs(dH)))h · \(f2(l.hrs))h logged, \(f2(s.regHours + s.otHours))h paid") }
        if abs(dP) > 0.005 { out.append("Per-diem \(word(dP)) \(money(abs(dP))) · \(money(l.perDiem)) logged, \(money(s.bonus)) paid") }
        return out
    }
}

struct StubField: View {
    let title: String
    let note: String
    var icon: String? = nil
    let value: Double
    let onCommit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    // Commits when focus leaves, so a database write happens once per edit.
    var body: some View {
        HStack {
            let label = VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(Theme.muted)
            }
            if let icon { Label { label } icon: { Image(systemName: icon) } } else { label }
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(Theme.mono(17)).frame(width: 110)
                .focused($focused)
                .onChange(of: focused) { _, f in if !f { commit() } }
        }
        .onAppear { text = shown }
        .onChange(of: value) { _, _ in if !focused { text = shown } }
        .onDisappear(perform: commit)
    }

    private var shown: String { value == 0 ? "" : String(format: "%g", value) }

    private func commit() {
        let v = Double(text) ?? 0
        if abs(v - value) > 1e-9 { onCommit(v) }
    }
}

private struct TuitionStatusSection: View {
    @Environment(AppModel.self) private var model
    let period: Period

    var body: some View {
        let data = model.data
        let ev = data.tuition.first { $0.periodStart == period.key }
        let owed = tuitionOwed(data, period)
        let expected = tuitionExpected(data, period, todayIso())
        Section {
            Picker("Tuition", selection: Binding(
                get: { ev?.status.rawValue ?? "unset" },
                set: { v in
                    switch v {
                    case "received": model.setTuition(period.key, .received, amount: ev?.amount ?? owed.amount)
                    case "missed": model.setTuition(period.key, .missed)
                    default: model.setTuition(period.key, nil)
                    }
                }
            )) {
                Text("Came through").tag("received")
                Text("Didn't").tag("missed")
                Text("Not sure").tag("unset")
            }
            .pickerStyle(.segmented)
            if let ev, ev.status == .received {
                StubField(title: "Amount", note: "owed was about \(money(owed.amount))", value: ev.amount) {
                    model.setTuition(period.key, .received, amount: $0)
                }
            }
        } header: {
            Text("Tuition on this check")
        } footer: {
            Text(ev == nil ? (expected ? "Expected here, not confirmed yet." : "Not expected on this check.") : "")
        }
    }
}
