import XCTest
@testable import PrepayCore

// Mirrors src/lib/pay.test.ts so both apps are held to the same numbers.

private func day(_ date: ISODate, _ f: (inout Day) -> Void = { _ in }) -> Day {
    var d = Day(date: date, startMin: 480, endMin: 990, lunch: true)
    f(&d)
    return d
}

private func data(days: [Day] = [], tuition: [TuitionEvent] = [], settings: Settings? = nil) -> PrepayData {
    var s = Settings.defaults(today: "2026-01-01")
    if let settings { s = settings }
    return PrepayData(days: days, rates: [Rate(effectiveFrom: "2000-01-01", rate: 20)], settings: s, tuition: tuition)
}

private func total(_ date: ISODate, _ h: Double) -> Day {
    day(date) { $0.mode = .total; $0.totalHours = h }
}

final class PayTests: XCTestCase {
    func testHolidays() {
        XCTAssertEqual(holidayOn("2026-01-01"), "New Year's Day")
        XCTAssertEqual(holidayOn("2026-05-25"), "Memorial Day")
        XCTAssertEqual(holidayOn("2026-09-07"), "Labor Day")
        XCTAssertEqual(holidayOn("2026-11-26"), "Thanksgiving")
        XCTAssertEqual(holidayOn("2026-12-25"), "Christmas")
        XCTAssertEqual(holidayOn("2026-07-03"), "Independence Day") // Sat Jul 4 -> Fri
        XCTAssertNil(holidayOn("2026-07-04"))
        XCTAssertEqual(holidayOn("2022-12-26"), "Christmas") // Sun Dec 25 -> Mon
        XCTAssertNil(holidayOn("2022-12-25"))
        XCTAssertEqual(holidayOn("2027-12-31"), "New Year's Day") // Sat Jan 1 2028 -> Fri
        XCTAssertEqual(holidayOn("2026-11-11"), "Veterans Day")
        XCTAssertEqual(holidayOn("2028-11-10"), "Veterans Day") // Sat Nov 11 -> Fri
        XCTAssertNil(holidayOn("2026-11-27"))
    }

    func testRoth() {
        var s = Settings.defaults(today: "2026-01-01")
        s.tuitionOn = false; s.rothPct = 6; s.rothFrom = "2026-11-01"
        let days = [day("2026-10-28") { $0.ccTips = 50 }, day("2026-11-03") { $0.ccTips = 50 }]
        XCTAssertEqual(estimate(data(days: days, settings: s), periodOf("2026-10-28"), "2026-11-13").totals.roth, 0)
        let t = estimate(data(days: days, settings: s), periodOf("2026-11-03"), "2026-11-13").totals
        var off = s; off.rothPct = 0
        let o = estimate(data(days: days, settings: off), periodOf("2026-11-03"), "2026-11-13").totals
        XCTAssertEqual(t.roth, 0.06 * t.gross, accuracy: 1e-9)
        XCTAssertEqual(t.match, t.roth, accuracy: 1e-9)
        XCTAssertEqual(t.tax, o.tax, accuracy: 1e-9)
        XCTAssertEqual(t.net, o.net - t.roth, accuracy: 1e-9)
        s.rothPct = 10
        let ten = estimate(data(days: [day("2026-11-03")], settings: s), periodOf("2026-11-03"), "2026-11-13").totals
        XCTAssertEqual(ten.roth, 16, accuracy: 1e-9)
        XCTAssertEqual(ten.match, 9.6, accuracy: 1e-9)
    }

    func testHolidayHoursDontStack() {
        // 36h Mon-Wed, 8h on Thanksgiving, 8h Friday
        let days = [total("2026-11-23", 12), total("2026-11-24", 12), total("2026-11-25", 12),
                    total("2026-11-26", 8), total("2026-11-27", 8)]
        let c = computeHours(days).values
        XCTAssertEqual(c.reduce(0) { $0 + $1.reg }, 36, accuracy: 1e-9)
        XCTAssertEqual(c.reduce(0) { $0 + $1.hol }, 8, accuracy: 1e-9)
        XCTAssertEqual(c.reduce(0) { $0 + $1.ot }, 8, accuracy: 1e-9)
    }

    func testHolidayPushesLaterDaysIntoOvertime() {
        let days = [total("2026-09-07", 8)] + ["08", "09", "10", "11"].map { total("2026-09-\($0)", 9) }
        let c = computeHours(days).values
        XCTAssertEqual(c.reduce(0) { $0 + $1.hol }, 8, accuracy: 1e-9)
        XCTAssertEqual(c.reduce(0) { $0 + $1.ot }, 4, accuracy: 1e-9)
        XCTAssertEqual(c.reduce(0) { $0 + $1.reg }, 32, accuracy: 1e-9)
    }

    func testHolidayPayInEstimateAndStub() {
        let t = estimate(data(days: [total("2026-11-26", 8), total("2026-11-25", 8)]), periodOf("2026-11-26"), "2026-11-27").totals
        XCTAssertEqual(t.holPay, 240, accuracy: 1e-9)
        XCTAssertEqual(t.waBase, 160 + 240, accuracy: 1e-9)
        XCTAssertEqual(t.hrs, 16, accuracy: 1e-9)
        let s = Stub(periodStart: "2026-11-16", periodEnd: "2026-11-30", payDate: "2026-12-04", regHours: 60, otHours: 0,
                     holHours: 8, ccTips: 0, bonus: 0, reimbursement: 0, tax: 0, taxIsEstimate: false, cashTips: 0)
        let p = stubTotals(s, rate: 13.5)
        XCTAssertEqual(p.holPay, 162)
        XCTAssertEqual(p.gross, 972)
        XCTAssertEqual(p.hours, 68)
    }

    func testPeriods() {
        let p = periodOf("2026-08-15")
        XCTAssertEqual([p.key, p.to, p.payDate], ["2026-08-01", "2026-08-15", "2026-08-20"])
        XCTAssertEqual(periodOf("2026-08-31").payDate, "2026-09-04") // Sep 5 is a Saturday
        XCTAssertEqual(periodOf("2026-12-20").payDate, "2027-01-05")
        XCTAssertEqual(periodOf("2026-02-20").to, "2026-02-28")
    }

    func testPayDayRollover() {
        let cal = Calendar(identifier: .gregorian)
        let before = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 6, minute: 59))!
        let after = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 7))!
        XCTAssertEqual(upcomingPeriod(before).key, "2026-08-01")
        XCTAssertEqual(upcomingPeriod(after).key, "2026-08-16")
    }

    func testOvertime() {
        let days = ["01", "02", "03", "04", "05", "06"].map { day("2026-08-\($0)") }
        let ot = computeHours(days).values.reduce(0) { $0 + $1.ot }
        XCTAssertEqual(ot, 8, accuracy: 1e-9)
    }

    func testPerDiemTaxedAsWages() {
        let d = data(days: [day("2026-08-03") { $0.travel = .partial }, day("2026-08-04") { $0.travel = .full }])
        let e = estimate(d, periodOf("2026-08-03"), "2026-08-10")
        XCTAssertEqual(e.totals.perDiem, 126)
        XCTAssertEqual(e.totals.waBase, 16 * 20 + 126, accuracy: 1e-9)
    }

    func testFederalBrackets() {
        XCTAssertEqual(federalTax(600), 0)
        XCTAssertEqual(federalTax(1000), 0.10 * (1000 - 670.83), accuracy: 1e-9)
        XCTAssertEqual(federalTax(4000), 51.667 + 190.0 + 0.22 * (4000 - 2770.83), accuracy: 0.01)
    }

    func testStubRounding() {
        let s = Stub(periodStart: "2026-08-01", periodEnd: "2026-08-15", payDate: "2026-08-20", regHours: 10, otHours: 1.01,
                     ccTips: 5, bonus: 51, sickHours: 2, reimbursement: 7, tax: 20, taxIsEstimate: false, cashTips: 0)
        let p = stubTotals(s, rate: 13.5)
        XCTAssertEqual(p.otPay, 20.46, accuracy: 1e-9)
        XCTAssertEqual(p.sickPay, 27, accuracy: 1e-9)
        XCTAssertEqual(p.gross, 135 + 20.46 + 27 + 5 + 51, accuracy: 1e-9)
    }

    func testRaiseBecomesBase() {
        let rates = [Rate(effectiveFrom: "2000-01-01", rate: 20), Rate(effectiveFrom: "2026-09-01", rate: 22)]
        XCTAssertEqual(currentRate(rates, "2026-08-20")?.rate, 20)
        XCTAssertEqual(pendingRaise(rates, "2026-08-20")?.rate, 22)
        XCTAssertEqual(currentRate(rates, "2026-09-01")?.rate, 22)
        XCTAssertNil(pendingRaise(rates, "2026-09-01"))
        XCTAssertEqual(rateFor(rates, "2026-08-31"), 20)
    }

    func testSickLedger() {
        let days = (3...12).map { day(String(format: "2026-08-%02d", $0)) }
        var d = data(days: days, settings: Settings(defaultStartMin: 465, defaultLunch: true, mileRate: 0.7, tuitionOn: true,
                                                     tuitionRate: 1, sickBalance: 10, sickAsOf: "2026-08-01"))
        XCTAssertEqual(sickLedger(d, "2026-08-19").available, 10)
        XCTAssertEqual(sickLedger(d, "2026-08-20").available, 12)
        d.cashouts = [Cashout(periodStart: "2026-08-16", hours: 5)]
        XCTAssertEqual(sickLedger(d, "2026-08-20").available, 7)
    }

    func testTuitionCadence() {
        let days = ["2026-06-20", "2026-07-02", "2026-07-20", "2026-08-03", "2026-08-20"].map { day($0) }
        var d = data(days: days, tuition: [TuitionEvent(periodStart: "2026-06-16", status: .received, amount: 50)])
        XCTAssertFalse(tuitionExpected(d, periodOf("2026-07-01"), "2026-07-01"))
        XCTAssertTrue(tuitionExpected(d, periodOf("2026-07-16"), "2026-07-01"))
        XCTAssertEqual(tuitionQuestions(d, "2026-08-06").map(\.key), ["2026-07-16"])
        XCTAssertEqual(tuitionOwed(d, periodOf("2026-08-01")).amount, 24)
        d.tuition.append(TuitionEvent(periodStart: "2026-07-16", status: .missed, amount: 0))
        XCTAssertTrue(tuitionExpected(d, periodOf("2026-08-01"), "2026-08-10"))
        XCTAssertFalse(tuitionExpected(d, periodOf("2026-08-16"), "2026-08-10"))
    }

    func testStats() {
        let days = [
            day("2026-08-01") { $0.ccTips = 50 }, day("2026-08-02") { $0.cashTips = 30 }, day("2026-08-03") { $0.endMin = 1200 },
            day("2026-08-10") { $0.mode = .total; $0.totalHours = 2 },
        ]
        let s = computeStats(days, [Rate(effectiveFrom: "2000-01-01", rate: 20)], "2026-08-11")
        XCTAssertEqual(s.longestStreak, Run(from: "2026-08-01", to: "2026-08-03", days: 3))
        XCTAssertEqual(s.longestBreak, Run(from: "2026-08-04", to: "2026-08-09", days: 6))
        XCTAssertEqual(s.longestDay?.date, "2026-08-03")
        XCTAssertEqual(s.shortestDay?.date, "2026-08-10")
        XCTAssertEqual(s.mostCash?.date, "2026-08-02")
        XCTAssertEqual(s.currentStreak, 1)
    }
}
