import Foundation

// A port of src/lib/pay.ts. Keep the two in step: the web app and the phone
// read the same rows and should come to the same numbers.

public let OT_MULT = 1.5
public let LUNCH_MIN = 30

/// Fixed per-day amounts. Payroll pays them as a "spot bonus", taxed as wages.
public func perDiem(_ t: Travel) -> Double {
    switch t { case .none: 0; case .partial: 51; case .full: 75 }
}

// Rates read off the ADP stubs. FLI/Cares/MLI are levied on wages + bonus and
// skip tips; Workers Comp is per hour actually worked.
enum TAX {
    static let fed = 0.12, fedAllow = 757.0, ss = 0.062, med = 0.0145
    static let fli = 0.005433, cares = 0.0058, mli = 0.002643, wc = 0.3519
}

public func cents(_ x: Double) -> Double { (x * 100).rounded() / 100 }

public func money(_ n: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return (n < 0 ? "−$" : "$") + (f.string(from: NSNumber(value: abs(n))) ?? "0.00")
}

public func dayHours(_ d: Day) -> Double {
    if d.mode == .total { return max(0, d.totalHours ?? 0) }
    var m = d.endMin - d.startMin
    if m < 0 { m += 1440 }
    if d.lunch { m -= LUNCH_MIN }
    return max(0, Double(m) / 60)
}

// MARK: - rates

private func byFrom(_ rates: [Rate]) -> [Rate] { rates.sorted { $0.effectiveFrom < $1.effectiveFrom } }

/// A raise applies to whole periods, so a date resolves through its period.
public func rateFor(_ rates: [Rate], _ date: ISODate) -> Double {
    let key = periodOf(date).key
    let sorted = byFrom(rates)
    return sorted.last(where: { $0.effectiveFrom <= key })?.rate ?? sorted.first?.rate ?? 0
}

/// The rate in force today. Once a raise's date arrives it simply is this.
public func currentRate(_ rates: [Rate], _ today: ISODate) -> Rate? {
    let sorted = byFrom(rates)
    return sorted.last(where: { $0.effectiveFrom <= today }) ?? sorted.first
}

public func pendingRaise(_ rates: [Rate], _ today: ISODate) -> Rate? {
    let cur = currentRate(rates, today)
    return byFrom(rates).first { $0.effectiveFrom > today && $0 != cur }
}

// MARK: - hours

public struct DayCalc: Sendable {
    public var hours = 0.0, reg = 0.0, ot = 0.0
    public init(hours: Double = 0, reg: Double = 0, ot: Double = 0) { self.hours = hours; self.reg = reg; self.ot = ot }
}

/// OT accrues within a Sat–Fri week on the hours past 40, in date order.
public func computeHours(_ days: [Day]) -> [UUID: DayCalc] {
    var run: [ISODate: Double] = [:]
    var out: [UUID: DayCalc] = [:]
    for d in days.sorted(by: { $0.date < $1.date }) {
        let k = weekStart(d.date)
        let h = dayHours(d)
        let before = run[k] ?? 0, after = before + h
        let ot = max(0, after - 40) - max(0, before - 40)
        out[d.id] = DayCalc(hours: h, reg: h - ot, ot: ot)
        run[k] = after
    }
    return out
}

public func daysIn(_ days: [Day], _ p: Period) -> [Day] { days.filter { $0.date >= p.from && $0.date <= p.to } }

/// Hours a period actually paid: the stub wins where there is one.
public func periodHours(_ data: PrepayData, _ p: Period, _ calc: [UUID: DayCalc]) -> Double {
    if let s = data.stubs.first(where: { $0.periodStart == p.key }) { return s.regHours + s.otHours }
    return daysIn(data.days, p).reduce(0) { $0 + (calc[$1.id]?.hours ?? 0) }
}

// MARK: - totals

public struct Totals: Sendable {
    public var reg = 0.0, ot = 0.0, hrs = 0.0, tips = 0.0, cash = 0.0
    public var perDiem = 0.0, travelDays = 0, miles = 0.0, milePay = 0.0
    public var rate = 0.0, sick = 0.0, sickPay = 0.0, tuition = 0.0
    public var regPay = 0.0, otPay = 0.0, waBase = 0.0, gross = 0.0
    public var taxLines: [(String, Double)] = []
    public var tax = 0.0, net = 0.0
}

public func totals(_ list: [Day], _ calc: [UUID: DayCalc], rate: Double, mileRate: Double,
                   sick: Double = 0, tuition: Double = 0) -> Totals {
    var t = Totals()
    for d in list {
        let c = calc[d.id] ?? DayCalc()
        t.reg += c.reg; t.ot += c.ot; t.hrs += c.hours
        t.tips += d.ccTips; t.cash += d.cashTips; t.miles += d.miles
        t.perDiem += perDiem(d.travel)
        if d.travel != .none { t.travelDays += 1 }
    }
    t.rate = rate
    t.regPay = t.reg * rate; t.otPay = t.ot * rate * OT_MULT
    t.sick = sick; t.sickPay = sick * rate
    t.milePay = t.miles * mileRate
    t.tuition = tuition
    // Tips are taxed federally but sit outside the Washington premiums;
    // per-diem comes through as a bonus and is taxed like wages; tuition and
    // mileage are reimbursements, outside all of it.
    t.waBase = t.regPay + t.otPay + t.sickPay + t.perDiem
    t.gross = t.waBase + t.tips
    t.taxLines = [
        ("Federal income tax", max(0, TAX.fed * (t.gross - TAX.fedAllow))),
        ("Social Security", TAX.ss * t.gross),
        ("Medicare", TAX.med * t.gross),
        ("Washington FLI", TAX.fli * t.waBase),
        ("Washington Cares", TAX.cares * t.waBase),
        ("Washington MLI", TAX.mli * t.waBase),
        ("WA Workers Comp", TAX.wc * t.hrs),
    ]
    t.tax = t.taxLines.reduce(0) { $0 + $1.1 }
    t.net = t.gross - t.tax + t.tuition + t.milePay
    return t
}

public struct StubTotals: Sendable { public var regPay, otPay, gross, hours, net: Double }

public func stubTotals(_ s: Stub, rate: Double) -> StubTotals {
    // payroll rounds each earnings line to cents before summing
    let regPay = cents(s.regHours * rate), otPay = cents(s.otHours * rate * OT_MULT)
    let gross = cents(regPay + otPay + s.ccTips + s.bonus)
    return StubTotals(regPay: regPay, otPay: otPay, gross: gross, hours: s.regHours + s.otHours,
                      net: cents(gross - s.tax + s.reimbursement))
}

// MARK: - sick hours

public func accrualFor(_ hours: Double) -> Double { floor(hours) / 40 }

public struct SickLedger: Sendable { public var available, accrued, cashed: Double }

/// Balance = the stub's figure on sickAsOf, plus accrual on every check paid
/// since, minus every cash-out paid or scheduled since.
public func sickLedger(_ data: PrepayData, _ today: ISODate, _ calc: [UUID: DayCalc]? = nil) -> SickLedger {
    let calc = calc ?? computeHours(data.days)
    let asOf = data.settings.sickAsOf
    var accrued = 0.0
    var p = prevPeriod(prevPeriod(periodOf(asOf)))
    while p.payDate <= today {
        if p.payDate > asOf { accrued += accrualFor(periodHours(data, p, calc)) }
        p = nextPeriod(p)
    }
    let cashed = data.cashouts.filter { periodOf($0.periodStart).payDate > asOf }.reduce(0) { $0 + $1.hours }
    return SickLedger(available: data.settings.sickBalance + accrued - cashed, accrued: accrued, cashed: cashed)
}

// MARK: - tuition

/// HR keys tuition in by hand, roughly every other check. It is expected two
/// checks after the last one it landed on; if an expected check passes
/// without it (marked missed, or never answered) it moves to the next check.
public let TUITION_EVERY = 2

public func lastTuitionReceived(_ data: PrepayData, before: ISODate) -> TuitionEvent? {
    data.tuition.filter { $0.status == .received && $0.periodStart < before }.max { $0.periodStart < $1.periodStart }
}

public func tuitionExpected(_ data: PrepayData, _ p: Period, _ today: ISODate) -> Bool {
    guard data.settings.tuitionOn else { return false }
    if let ev = data.tuition.first(where: { $0.periodStart == p.key }) { return ev.status == .received }
    guard let last = lastTuitionReceived(data, before: p.key) else { return true }
    var e = shiftPeriod(periodOf(last.periodStart), TUITION_EVERY)
    while e.key < p.key {
        let ev = data.tuition.first { $0.periodStart == e.key }
        let passed = ev.map { $0.status == .missed } ?? (e.payDate <= today)
        if !passed { return false }
        e = nextPeriod(e)
    }
    return e.key == p.key
}

public struct TuitionOwed: Sendable { public var amount: Double, hours: Double }

/// A payout on period P settles hours through P-1, so the window opens AT
/// the last paid period, not after it.
public func tuitionOwed(_ data: PrepayData, _ p: Period, _ calc: [UUID: DayCalc]? = nil) -> TuitionOwed {
    let calc = calc ?? computeHours(data.days)
    let first = lastTuitionReceived(data, before: p.key)?.periodStart
        ?? (data.days.map { periodOf($0.date).key } + data.stubs.map(\.periodStart)).min()
    var hours = 0.0
    if let first {
        var q = periodOf(first)
        while q.key < p.key { hours += periodHours(data, q, calc); q = nextPeriod(q) }
    }
    return TuitionOwed(amount: cents(hours * data.settings.tuitionRate), hours: hours)
}

/// Recent paid checks where tuition was expected and nobody has said whether it came.
public func tuitionQuestions(_ data: PrepayData, _ today: ISODate) -> [Period] {
    guard data.settings.tuitionOn else { return [] }
    var out: [Period] = []
    var p = periodOf(addDays(today, -45))
    while p.payDate <= today {
        let asked = data.tuition.contains { $0.periodStart == p.key }
        let active = data.days.contains { $0.date < p.from } || data.stubs.contains { $0.periodStart < p.key }
        if !asked && active && tuitionExpected(data, p, today) { out.append(p) }
        p = nextPeriod(p)
    }
    return out
}

// MARK: - one period

public struct Estimate: Sendable {
    public var period: Period
    public var list: [Day]
    public var totals: Totals
    public var tuitionExpected: Bool
    public var tuitionOwed: TuitionOwed
    public var accrual: Double
}

public func estimate(_ data: PrepayData, _ p: Period, _ today: ISODate, _ calc: [UUID: DayCalc]? = nil) -> Estimate {
    let calc = calc ?? computeHours(data.days)
    let list = daysIn(data.days, p)
    let sick = data.cashouts.first { $0.periodStart == p.key }?.hours ?? 0
    let expected = tuitionExpected(data, p, today)
    let ev = data.tuition.first { $0.periodStart == p.key }
    let owed = tuitionOwed(data, p, calc)
    let tuition = !expected ? 0 : ev?.status == .received ? ev!.amount : owed.amount
    let t = totals(list, calc, rate: rateFor(data.rates, p.from), mileRate: data.settings.mileRate, sick: sick, tuition: tuition)
    return Estimate(period: p, list: list, totals: t, tuitionExpected: expected, tuitionOwed: owed, accrual: accrualFor(t.hrs))
}
