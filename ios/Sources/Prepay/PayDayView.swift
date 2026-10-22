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
                VStack(alignment: .leading, spacing: 16) {
                    if data.rates.isEmpty {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "exclamationmark.circle.fill")
                            Text("Set your hourly rate in Settings to see an estimate.").font(.callout)
                        }
                        .card()
                    }

                    // The check itself.
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Caps("Pay day · \(fmtMD(pay.payDate))", color: Theme.paper.opacity(0.65))
                            Spacer()
                            Image(systemName: "dollarsign.circle.fill").foregroundStyle(Theme.accentLight)
                        }
                        Text(money(t.net))
                            .font(Theme.serif(56, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .padding(.top, 8)
                        Text(t.gross > 0 ? "net estimate · gross \(money(t.gross))" : t.tuition > 0 ? "reimbursement only · nothing logged yet" : "nothing logged yet")
                            .font(.subheadline).foregroundStyle(Theme.paper.opacity(0.7))

                        PeriodBar(value: elapsed, total: total).padding(.top, 22)
                        HStack {
                            Caps(fmtRange(pay), color: Theme.paper.opacity(0.65))
                            Spacer()
                            Caps(daysOut <= 0 ? "Today" : closed ? "Closed · pays in \(daysOut) day\(daysOut == 1 ? "" : "s")" : "\(daysOut) day\(daysOut == 1 ? "" : "s") out",
                                 color: closed || daysOut <= 0 ? Theme.accentLight : Theme.paper.opacity(0.65))
                        }
                        .padding(.top, 8)
                    }
                    .foregroundStyle(Theme.paper)
                    .card(padding: 22, fill: Theme.ink, stroke: .clear)

                    // Where the number comes from.
                    VStack(alignment: .leading, spacing: 0) {
                        Caps("Breakdown").padding(.bottom, 6)
                        if t.reg > 0 { LineRow(name: "Regular", detail: "\(f2(t.reg))h @ \(f2(t.rate))", amount: money(t.regPay)) }
                        if t.ot > 0 { LineRow(name: "Overtime", detail: "\(f2(t.ot))h @ \(f2(t.rate * OT_MULT))", amount: money(t.otPay)) }
                        if t.tips > 0 { LineRow(name: "Credit card tips", amount: money(t.tips)) }
                        if t.perDiem > 0 { LineRow(name: "Per-diem", detail: "\(t.travelDays)d · spot bonus", amount: money(t.perDiem)) }
                        if t.sick > 0 { LineRow(name: "Sick cash-out", detail: "\(f2(t.sick))h", amount: money(t.sickPay)) }
                        Divider().padding(.vertical, 4)
                        LineRow(name: "Gross", amount: money(t.gross), bold: true)
                        LineRow(name: "Est. taxes & deductions", amount: "−" + money(t.tax), dim: true)
                        if t.milePay > 0 { LineRow(name: "POV mileage", detail: "\(String(format: "%g", t.miles)) mi", amount: money(t.milePay)) }
                        if t.tuition > 0 { LineRow(name: "Tuition reimb.", detail: "expected", amount: money(t.tuition)) }
                        Divider().padding(.vertical, 4)
                        LineRow(name: "Net", amount: money(t.net), bold: true)

                        DisclosureGroup(isExpanded: $showTax.animation(.snappy)) {
                            VStack(spacing: 6) {
                                ForEach(t.taxLines.indices, id: \.self) { i in
                                    HStack { Text(t.taxLines[i].0); Spacer(); Text(money(t.taxLines[i].1)) }
                                        .font(Theme.mono(13)).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.top, 8)
                        } label: { Caps("Tax breakdown", color: Theme.accent) }
                        .tint(Theme.accent)
                        .padding(.top, 10)
                    }
                    .card()

                    if t.cash > 0 {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "banknote.fill", color: Theme.good)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cash tips pocketed")
                                Text("already yours — not part of the check").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(money(t.cash)).font(Theme.mono(17, weight: .semibold))
                        }
                        .card(stroke: Theme.good.opacity(0.35))
                    }

                    Label {
                        Text("Accruing \(f2(e.accrual)) sick h this period" + (data.settings.tuitionOn && !e.tuitionExpected ? " · no tuition expected" : ""))
                    } icon: { Image(systemName: "cross.case") }
                    .font(.footnote).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)

                    ForEach(tuitionQuestions(data, today), id: \.key) { p in
                        TuitionAsk(period: p)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Caps("Logged days")
                            Spacer()
                            Caps("Tap to edit")
                        }
                        .padding(.bottom, 6)
                        if e.list.isEmpty {
                            Text("No days logged for this period yet.").foregroundStyle(Theme.muted).padding(.vertical, 12)
                        }
                        let days = e.list.sorted { $0.date > $1.date }
                        ForEach(days) { d in
                            if d.id != days.first?.id { Divider() }
                            DayRowView(day: d, calc: calc)
                        }
                    }
                    .card()

                    if !n.list.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Caps("Next check")
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pay day \(fmtMD(next.payDate))").fontWeight(.semibold)
                                    Caps("\(fmtRange(next)) · \(n.list.count) days")
                                }
                                Spacer()
                                Text(money(n.totals.net)).font(Theme.serif(26, weight: .semibold))
                            }
                            .padding(.top, 6).padding(.bottom, 8)
                            let days = n.list.sorted { $0.date > $1.date }
                            ForEach(days) { d in
                                Divider()
                                DayRowView(day: d, calc: calc)
                            }
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper)
            .navigationTitle("Pay day")
            .refreshable { await model.load() }
        }
    }
}

/// How far through the pay period today is.
struct PeriodBar: View {
    let value: Double
    let total: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.paper.opacity(0.18))
                Capsule().fill(Theme.accent)
                    .frame(width: total > 0 ? max(6, g.size.width * min(1, value / total)) : 0)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Pay period progress")
        .accessibilityValue("\(Int(value)) of \(Int(total)) days")
    }
}

struct TuitionAsk: View {
    @Environment(AppModel.self) private var model
    let period: Period
    @State private var amount = 0.0
    @State private var primed = false

    var body: some View {
        let owed = tuitionOwed(model.data, period)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemImage: "graduationcap.fill")
                Caps("Tuition check-in", color: Theme.accent)
            }
            Text("Did tuition reimbursement come through on the \(fmtMD(period.payDate)) check?").font(.headline)
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
            .controlSize(.large)
        }
        .card(stroke: Theme.accent.opacity(0.4))
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
        let date = dparse(day.date)
        Button { model.edit(day) } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Theme.mono(9, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(date.formatted(.dateTime.day())).font(Theme.serif(19, weight: .semibold))
                }
                .frame(width: 42, height: 44)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(fmtFull(day.date)).fontWeight(.medium)
                    Text(detail).font(Theme.mono(11)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(money(amount)).font(Theme.mono(15, weight: .medium))
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func f2(_ x: Double) -> String { String(format: "%.2f", x) }
