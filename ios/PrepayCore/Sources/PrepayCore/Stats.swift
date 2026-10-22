import Foundation

// A port of src/lib/stats.ts.

public struct DayStat: Sendable { public var date: ISODate; public var value: Double }
public struct Run: Sendable, Equatable { public var from: ISODate; public var to: ISODate; public var days: Int }

public struct Stats: Sendable {
    public var daysWorked = 0
    public var totalHours = 0.0
    public var totalEarned = 0.0 // wages + CC tips + cash tips
    public var totalCcTips = 0.0
    public var totalCash = 0.0
    public var totalPerDiem = 0.0
    public var totalMiles = 0.0
    public var travelDays = 0
    public var avgHourly = 0.0
    public var highestDay: DayStat?
    public var lowestDay: DayStat?
    public var longestDay: DayStat?
    public var shortestDay: DayStat?
    public var mostCash: DayStat?
    public var mostCcTips: DayStat?
    public var mostMiles: DayStat?
    public var bestWeek: DayStat? // date = the Saturday it starts on
    public var longestStreak: Run?
    public var longestBreak: Run?
    public var currentStreak = 0
    public var earliestStart: (date: ISODate, label: String)?
    public var latestEnd: (date: ISODate, label: String)?
    public var busiestWeekday: (name: String, count: Int)?
}

private struct DayAgg { var hours = 0.0, earned = 0.0, cash = 0.0, cc = 0.0, miles = 0.0 }

/// Several entries on one date (a split shift) count as one day.
public func computeStats(_ days: [Day], _ rates: [Rate], _ today: ISODate) -> Stats {
    let calc = computeHours(days)
    var s = Stats()
    var byDate: [ISODate: DayAgg] = [:]
    var weekday = Array(repeating: 0, count: 7)
    var earliestMin = Int.max, latestMin = Int.min

    for d in days {
        let c = calc[d.id] ?? DayCalc()
        let rate = rateFor(rates, d.date)
        if byDate[d.date] == nil {
            weekday[Calendar(identifier: .gregorian).component(.weekday, from: dparse(d.date)) - 1] += 1
        }
        var e = byDate[d.date] ?? DayAgg()
        e.hours += c.hours
        e.earned += c.reg * rate + c.ot * rate * OT_MULT + d.ccTips + d.cashTips
        e.cash += d.cashTips; e.cc += d.ccTips; e.miles += d.miles
        byDate[d.date] = e
        s.totalPerDiem += perDiem(d.travel)
        if d.travel != .none { s.travelDays += 1 }
        if d.mode == .range {
            if d.startMin < earliestMin { earliestMin = d.startMin; s.earliestStart = (d.date, fmtTime(d.startMin)) }
            // a shift past midnight ends "later" than any same-day clock-out
            let end = d.endMin < d.startMin ? d.endMin + 1440 : d.endMin
            if end > latestMin { latestMin = end; s.latestEnd = (d.date, fmtTime(d.endMin)) }
        }
    }

    let dates = byDate.keys.sorted()
    let worked = dates.filter { byDate[$0]!.hours > 0 }
    func stat(_ f: (DayAgg) -> Double, _ from: [ISODate]) -> [DayStat] { from.map { DayStat(date: $0, value: f(byDate[$0]!)) } }
    func best(_ xs: [DayStat], _ better: (Double, Double) -> Bool) -> DayStat? {
        xs.reduce(nil as DayStat?) { b, x in b == nil || better(x.value, b!.value) ? x : b }
    }

    let earned = stat({ $0.earned }, worked)
    let hours = stat({ $0.hours }, worked)
    s.highestDay = best(earned, >); s.lowestDay = best(earned, <)
    s.longestDay = best(hours, >); s.shortestDay = best(hours, <)
    s.mostCash = best(stat({ $0.cash }, worked).filter { $0.value > 0 }, >)
    s.mostCcTips = best(stat({ $0.cc }, worked).filter { $0.value > 0 }, >)
    s.mostMiles = best(stat({ $0.miles }, worked).filter { $0.value > 0 }, >)

    var weeks: [ISODate: Double] = [:]
    for k in dates { weeks[weekStart(k), default: 0] += byDate[k]!.earned }
    s.bestWeek = best(weeks.map { DayStat(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }, >)

    // runs of consecutive calendar days worked, and the gaps between them
    var runStart: ISODate?, prev: ISODate?
    func closeRun(_ end: ISODate) {
        let n = daysBetween(runStart!, end) + 1
        if s.longestStreak == nil || n > s.longestStreak!.days { s.longestStreak = Run(from: runStart!, to: end, days: n) }
    }
    for k in worked {
        if let p = prev, daysBetween(p, k) == 1 { prev = k; continue }
        if let p = prev {
            closeRun(p)
            let gap = daysBetween(p, k) - 1
            if s.longestBreak == nil || gap > s.longestBreak!.days {
                s.longestBreak = Run(from: addDays(p, 1), to: addDays(k, -1), days: gap)
            }
        }
        runStart = k; prev = k
    }
    if let p = prev { closeRun(p) }

    // the streak still going: counts today, or yesterday if today isn't logged yet
    let set = Set(worked)
    var cur = set.contains(today) ? today : addDays(today, -1)
    while set.contains(cur) { s.currentStreak += 1; cur = addDays(cur, -1) }

    s.daysWorked = worked.count
    s.totalHours = hours.reduce(0) { $0 + $1.value }
    s.totalEarned = earned.reduce(0) { $0 + $1.value }
    s.totalCcTips = dates.reduce(0) { $0 + byDate[$1]!.cc }
    s.totalCash = dates.reduce(0) { $0 + byDate[$1]!.cash }
    s.totalMiles = dates.reduce(0) { $0 + byDate[$1]!.miles }
    s.avgHourly = s.totalHours > 0 ? s.totalEarned / s.totalHours : 0
    let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    if let m = weekday.max(), m > 0, let i = weekday.firstIndex(of: m) { s.busiestWeekday = (names[i], m) }
    return s
}
