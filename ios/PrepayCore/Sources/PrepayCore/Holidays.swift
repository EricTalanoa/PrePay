import Foundation

// A port of src/lib/holidays.ts.
//
// Paid holidays: hours worked on one are paid at time and a half (HOL_MULT).
// Nothing is paid for a holiday not worked. A holiday on a Saturday is
// observed the Friday before, one on a Sunday the Monday after, and only the
// observed day earns the premium.

private var cal: Calendar { Calendar(identifier: .gregorian) }

/// month is 1-based, weekday 1 = Sunday (Calendar's numbering)
private func nthWeekday(_ y: Int, _ month: Int, _ weekday: Int, _ n: Int) -> Date {
    let first = cal.component(.weekday, from: ymd(y, month, 1))
    return ymd(y, month, 1 + (weekday - first + 7) % 7 + (n - 1) * 7)
}

private func lastWeekday(_ y: Int, _ month: Int, _ weekday: Int) -> Date {
    let last = cal.date(byAdding: .day, value: -1, to: ymd(y, month + 1, 1))! // month 13 rolls to January
    let c = cal.dateComponents([.day, .weekday], from: last)
    return ymd(y, month, c.day! - (c.weekday! - weekday + 7) % 7)
}

public let HOLIDAYS: [(name: String, on: @Sendable (Int) -> Date)] = [
    ("New Year's Day", { ymd($0, 1, 1) }),
    ("Memorial Day", { lastWeekday($0, 5, 2) }),
    ("Independence Day", { ymd($0, 7, 4) }),
    ("Labor Day", { nthWeekday($0, 9, 2, 1) }),
    ("Veterans Day", { ymd($0, 11, 11) }),
    ("Thanksgiving", { nthWeekday($0, 11, 5, 4) }),
    ("Christmas", { ymd($0, 12, 25) }),
]

private func observed(_ d: Date) -> Date {
    switch cal.component(.weekday, from: d) {
    case 7: return cal.date(byAdding: .day, value: -1, to: d)!
    case 1: return cal.date(byAdding: .day, value: 1, to: d)!
    default: return d
    }
}

/// The holiday observed on this date, if any. Next year's list is checked
/// too: a Saturday New Year's Day is observed on Dec 31.
public func holidayOn(_ date: ISODate) -> String? {
    let y = cal.component(.year, from: dparse(date))
    for yr in [y, y + 1] {
        for h in HOLIDAYS where iso(observed(h.on(yr))) == date { return h.name }
    }
    return nil
}
