import PrepayCore
import SwiftUI

struct PayDayView: View {
    @Environment(AppModel.self) private var model
    @State private var showTax = false

    var body: some View {
        let data = model.data
        let today = todayIso()
        let pay = upcomingPeriod()
        let calc = computeHours(data.days)
        let e = estimate(data, pay, today, calc)
        let t = e.totals
        let closed = today > pay.to
        let daysOut = daysBetween(today, pay.payDate)
        let total = Double(daysBetween(pay.from, pay.to) + 1)
        let elapsed = min(total, max(0, Double(daysBetween(pay.from, today) + 1)))
        let next = nextPeriod(pay)
        let n = estimate(data, next, today, calc)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if data.rates.isEmpty {
                        Text("Set your hourly rate in Settings to see an estimate.")
                            .foregroundStyle(Theme.muted).padding(.bottom, 16)
                    }
                    Text(money(t.net)).font(Theme.serif(60))
                    Text(t.gross > 0 ? "net estimate · gross \(money(t.gross))" : t.tuition > 0 ? "reimbursement only · nothing logged yet" : "nothing logged yet")
                        .foregroundStyle(Theme.muted).padding(.top, 4)

                    ProgressView(value: elapsed, total: total).tint(Theme.accent).padding(.top, 20)
                    HStack {
                        Caps(fmtRange(pay))
                        Spacer()
                        Caps(daysOut <= 0 ? "Today" : closed ? "Closed · pays in \(daysOut) day\(daysOut == 1 ? "" : "s")" : "\(daysOut) day\(daysOut == 1 ? "" : "s") out",
                             color: closed ? Theme.accent : Theme.muted)
                    }
                    .padding(.top, 6)

                    Divider().overlay(Theme.ink).padding(.top, 20)
                    if t.reg > 0 { LineRow(name: "Regular", detail: "\(f2(t.reg))h @ \(f2(t.rate))", amount: money(t.regPay)) }
                    if t.ot > 0 { LineRow(name: "Overtime", detail: "\(f2(t.ot))h @ \(f2(t.rate * OT_MULT))", amount: money(t.otPay)) }
                    if t.tips > 0 { LineRow(name: "Credit card tips", amount: money(t.tips)) }
                    if t.perDiem > 0 { LineRow(name: "Per-diem", detail: "\(t.travelDays)d · spot bonus", amount: money(t.perDiem)) }
                    if t.sick > 0 { LineRow(name: "Sick cash-out", detail: "\(f2(t.sick))h", amount: money(t.sickPay)) }
                    Divider()
                    LineRow(name: "Gross", amount: money(t.gross), bold: true)
                    LineRow(name: "Est. taxes & deductions", amount: "−" + money(t.tax), dim: true)
                    if t.milePay > 0 { LineRow(name: "POV mileage", detail: "\(String(format: "%g", t.miles)) mi", amount: money(t.milePay)) }
                    if t.tuition > 0 { LineRow(name: "Tuition reimb.", detail: "expected", amount: money(t.tuition)) }

                    if t.cash > 0 {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Cash tips pocketed")
                                Text("already yours — not part of the check").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(money(t.cash)).font(Theme.mono(17))
                        }
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.muted, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .padding(.top, 14)
                    }

                    Caps("Accruing \(f2(e.accrual)) sick h this period" + (data.settings.tuitionOn && !e.tuitionExpected ? " · no tuition expected" : ""))
                        .padding(.top, 14)

                    DisclosureGroup(isExpanded: $showTax) {
                        ForEach(t.taxLines.indices, id: \.self) { i in
                            HStack { Text(t.taxLines[i].0); Spacer(); Text(money(t.taxLines[i].1)) }
                                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
                        }
                    } label: { Caps("Tax breakdown", color: Theme.accent) }
                    .padding(.top, 12)

                    ForEach(tuitionQuestions(data, today), id: \.key) { p in
                        TuitionAsk(period: p).padding(.top, 20)
                    }

                    Caps("Logged days · tap to edit").padding(.top, 28)
                    if e.list.isEmpty {
                        Text("No days logged for this period yet.").foregroundStyle(Theme.muted).padding(.vertical, 12)
                    }
                    ForEach(e.list.sorted { $0.date > $1.date }) { d in DayRowView(day: d, calc: calc) }

                    if !n.list.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Caps("Next check")
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading) {
                                    Text("Pay day \(fmtMD(next.payDate))").fontWeight(.semibold)
                                    Caps("\(fmtRange(next)) · \(n.list.count) days")
                                }
                                Spacer()
                                Text(money(n.totals.net)).font(Theme.serif(26))
                            }
                            ForEach(n.list.sorted { $0.date > $1.date }) { d in DayRowView(day: d, calc: calc) }
                        }
                        .padding(16)
                        .overlay(Rectangle().stroke(Theme.ink))
                        .padding(.top, 28)
                    }
                }
                .padding(24)
            }
            .background(Theme.paper)
            .navigationTitle("Pay day — \(fmtMD(pay.payDate))")
            .refreshable { await model.load() }
        }
    }
}

struct TuitionAsk: View {
    @Environment(AppModel.self) private var model
    let period: Period
    @State private var amount = 0.0
    @State private var primed = false

    var body: some View {
        let owed = tuitionOwed(model.data, period)
        VStack(alignment: .leading, spacing: 10) {
            Caps("Tuition check-in", color: Theme.accent)
            Text("Did tuition reimbursement come through on the \(fmtMD(period.payDate)) check?")
            HStack {
                Text("Expected about \(money(owed.amount))").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                DecimalField(placeholder: "0.00", value: $amount, width: 100)
            }
            HStack {
                Button("No — next check") { model.setTuition(period.key, .missed) }.buttonStyle(.bordered)
                Spacer()
                Button("Yes") { model.setTuition(period.key, .received, amount: amount) }.buttonStyle(.borderedProminent)
            }
            .tint(Theme.ink)
        }
        .padding(16)
        .overlay(Rectangle().stroke(Theme.accent))
        .onAppear { if !primed { amount = owed.amount; primed = true } }
    }
}

struct DayRowView: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let calc: [UUID: DayCalc]

    private var detail: String {
        let hours = calc[day.id]?.hours ?? 0
        var parts = [day.mode == .total ? "\(f2(hours))h"
            : "\(fmtTime(day.startMin)) – \(fmtTime(day.endMin))\(day.lunch ? " · 30m" : "") · \(f2(hours))h"]
        if day.travel != .none { parts.append(day.travel == .full ? "away" : "travel") }
        if day.miles > 0 { parts.append("\(String(format: "%g", day.miles)) mi") }
        if day.cashTips > 0 { parts.append("\(money(day.cashTips)) cash") }
        return parts.joined(separator: " · ")
    }

    private var amount: Double {
        let c = calc[day.id] ?? DayCalc()
        let rate = rateFor(model.data.rates, day.date)
        return c.reg * rate + c.ot * rate * OT_MULT + day.ccTips + perDiem(day.travel)
    }

    var body: some View {
        Button { model.edit(day) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fmtFull(day.date)).fontWeight(.medium)
                    Text(detail).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(money(amount)).font(Theme.mono(15))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
    }
}

func f2(_ x: Double) -> String { String(format: "%.2f", x) }
