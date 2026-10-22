import Foundation

// Calendar helpers. Dates travel as local "YYYY-MM-DD" strings, as they do in
// the database and the web app, so string comparison is date comparison.

public typealias ISODate = String

private var cal: Calendar { Calendar(identifier: .gregorian) }

public func iso(_ d: Date) -> ISODate {
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

public func dparse(_ s: ISODate) -> Date {
    let p = s.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return Date() }
    return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
}

func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d))!
}

public func addDays(_ s: ISODate, _ n: Int) -> ISODate {
    iso(cal.date(byAdding: .day, value: n, to: dparse(s))!)
}

public func daysBetween(_ a: ISODate, _ b: ISODate) -> Int {
    cal.dateComponents([.day], from: dparse(a), to: dparse(b)).day ?? 0
}

public func todayIso(_ now: Date = Date()) -> ISODate { iso(now) }

private func weekday(_ s: ISODate) -> Int { cal.component(.weekday, from: dparse(s)) - 1 } // 0 = Sunday

/// Overtime is counted in Saturday–Friday weeks.
public func weekStart(_ s: ISODate) -> ISODate { addDays(s, -((weekday(s) + 1) % 7)) }

/// A pay date on a weekend moves back to the Friday before.
private func adjust(_ d: Date) -> Date {
    switch cal.component(.weekday, from: d) {
    case 7: return cal.date(byAdding: .day, value: -1, to: d)!
    case 1: return cal.date(byAdding: .day, value: -2, to: d)!
    default: return d
    }
}

public struct Period: Hashable, Sendable {
    public let key: ISODate // first day of the period; also its id
    public let from: ISODate
    public let to: ISODate
    public let payDate: ISODate
}

/// 1st–15th pays on the 20th; 16th–end of month pays on the 5th of the next.
public func periodOf(_ s: ISODate) -> Period {
    let c = cal.dateComponents([.year, .month, .day], from: dparse(s))
    let y = c.year!, m = c.month!
    if c.day! <= 15 {
        let from = iso(ymd(y, m, 1))
        return Period(key: from, from: from, to: iso(ymd(y, m, 15)), payDate: iso(adjust(ymd(y, m, 20))))
    }
    let next = cal.date(byAdding: .month, value: 1, to: ymd(y, m, 1))!
    let from = iso(ymd(y, m, 16))
    let to = iso(cal.date(byAdding: .day, value: -1, to: next)!)
    let payDate = iso(adjust(cal.date(byAdding: .day, value: 4, to: next)!))
    return Period(key: from, from: from, to: to, payDate: payDate)
}

public func nextPeriod(_ p: Period) -> Period { periodOf(addDays(p.to, 1)) }
public func prevPeriod(_ p: Period) -> Period { periodOf(addDays(p.from, -1)) }

public func shiftPeriod(_ p: Period, _ n: Int) -> Period {
    var q = p
    for _ in 0..<abs(n) { q = n > 0 ? nextPeriod(q) : prevPeriod(q) }
    return q
}

/// The check coming next. On pay day the money lands at 7 AM, so after that
/// the next check is the one after.
public func upcomingPeriod(_ now: Date = Date()) -> Period {
    let today = iso(now)
    let past7 = cal.component(.hour, from: now) >= 7
    var p = prevPeriod(prevPeriod(periodOf(today)))
    while past7 ? p.payDate <= today : p.payDate < today { p = nextPeriod(p) }
    return p
}

public func nowMinutes(_ now: Date = Date()) -> Int {
    let c = cal.dateComponents([.hour, .minute], from: now)
    return c.hour! * 60 + c.minute!
}

public func fmtTime(_ m: Int) -> String {
    let h = m / 60, mi = m % 60
    let hh = h % 12 == 0 ? 12 : h % 12
    return "\(hh):\(String(format: "%02d", mi)) \(h < 12 ? "AM" : "PM")"
}

private func fmt(_ s: ISODate, _ template: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: dparse(s))
}

public func fmtMD(_ s: ISODate) -> String { fmt(s, "MMMd") }
public func fmtFull(_ s: ISODate) -> String { fmt(s, "EEEMMMd") }
public func fmtRange(_ p: Period) -> String { "\(fmtMD(p.from)) – \(fmtMD(p.to))".uppercased() }
