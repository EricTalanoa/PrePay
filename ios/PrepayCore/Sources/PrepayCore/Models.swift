import Foundation

// These encode straight to the Supabase rows (snake_case columns). user_id is
// never sent: the database fills it from the signed-in user.

public enum Travel: String, Codable, CaseIterable, Sendable {
    case none, partial, full
}

public struct Day: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: ISODate
    public var mode: Mode
    public var startMin: Int
    public var endMin: Int
    public var totalHours: Double?
    public var lunch: Bool
    public var ccTips: Double
    public var cashTips: Double
    public var travel: Travel
    public var miles: Double

    public enum Mode: String, Codable, Sendable { case range, total }

    enum CodingKeys: String, CodingKey {
        case id, date, mode, lunch, travel, miles
        case startMin = "start_min", endMin = "end_min", totalHours = "total_hours"
        case ccTips = "cc_tips", cashTips = "cash_tips"
    }

    public init(id: UUID = UUID(), date: ISODate, mode: Mode = .range, startMin: Int, endMin: Int,
                totalHours: Double? = nil, lunch: Bool, ccTips: Double = 0, cashTips: Double = 0,
                travel: Travel = .none, miles: Double = 0) {
        self.id = id; self.date = date; self.mode = mode; self.startMin = startMin; self.endMin = endMin
        self.totalHours = totalHours; self.lunch = lunch; self.ccTips = ccTips; self.cashTips = cashTips
        self.travel = travel; self.miles = miles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        mode = try c.decode(Mode.self, forKey: .mode)
        startMin = try c.decodeIfPresent(Int.self, forKey: .startMin) ?? 0
        endMin = try c.decodeIfPresent(Int.self, forKey: .endMin) ?? 0
        totalHours = try c.decodeIfPresent(Double.self, forKey: .totalHours)
        lunch = try c.decode(Bool.self, forKey: .lunch)
        ccTips = try c.decode(Double.self, forKey: .ccTips)
        cashTips = try c.decode(Double.self, forKey: .cashTips)
        travel = try c.decode(Travel.self, forKey: .travel)
        miles = try c.decode(Double.self, forKey: .miles)
    }
}

public struct Stub: Codable, Hashable, Sendable {
    public var periodStart: ISODate
    public var periodEnd: ISODate
    public var payDate: ISODate
    public var regHours: Double
    public var otHours: Double
    public var ccTips: Double
    public var bonus: Double // the per-diem, which payroll prints as "spot bonus"
    public var sickHours: Double // cashed out on this check, at straight time
    public var reimbursement: Double
    public var tax: Double
    public var taxIsEstimate: Bool
    public var cashTips: Double

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start", periodEnd = "period_end", payDate = "pay_date"
        case regHours = "reg_hours", otHours = "ot_hours", ccTips = "cc_tips", bonus, reimbursement, tax
        case sickHours = "sick_hours"
        case taxIsEstimate = "tax_is_estimate", cashTips = "cash_tips"
    }

    public init(periodStart: ISODate, periodEnd: ISODate, payDate: ISODate, regHours: Double, otHours: Double,
                ccTips: Double, bonus: Double, sickHours: Double = 0, reimbursement: Double, tax: Double,
                taxIsEstimate: Bool, cashTips: Double) {
        self.periodStart = periodStart; self.periodEnd = periodEnd; self.payDate = payDate
        self.regHours = regHours; self.otHours = otHours; self.ccTips = ccTips; self.bonus = bonus; self.sickHours = sickHours
        self.reimbursement = reimbursement; self.tax = tax; self.taxIsEstimate = taxIsEstimate; self.cashTips = cashTips
    }
}

public struct Rate: Codable, Hashable, Sendable {
    public var effectiveFrom: ISODate
    public var rate: Double
    enum CodingKeys: String, CodingKey { case effectiveFrom = "effective_from", rate }
    public init(effectiveFrom: ISODate, rate: Double) { self.effectiveFrom = effectiveFrom; self.rate = rate }
}

public struct Cashout: Codable, Hashable, Sendable {
    public var periodStart: ISODate
    public var hours: Double
    enum CodingKeys: String, CodingKey { case periodStart = "period_start", hours }
    public init(periodStart: ISODate, hours: Double) { self.periodStart = periodStart; self.hours = hours }
}

public struct TuitionEvent: Codable, Hashable, Sendable {
    public var periodStart: ISODate
    public var status: Status
    public var amount: Double
    public enum Status: String, Codable, Sendable { case received, missed }
    enum CodingKeys: String, CodingKey { case periodStart = "period_start", status, amount }
    public init(periodStart: ISODate, status: Status, amount: Double) {
        self.periodStart = periodStart; self.status = status; self.amount = amount
    }
}

public struct Settings: Codable, Hashable, Sendable {
    public var defaultStartMin: Int
    public var defaultLunch: Bool
    public var mileRate: Double
    public var tuitionOn: Bool
    public var tuitionRate: Double
    public var sickBalance: Double
    public var sickAsOf: ISODate

    enum CodingKeys: String, CodingKey {
        case defaultStartMin = "default_start_min", defaultLunch = "default_lunch", mileRate = "mile_rate"
        case tuitionOn = "tuition_on", tuitionRate = "tuition_rate", sickBalance = "sick_balance", sickAsOf = "sick_as_of"
    }

    public static func defaults(today: ISODate = todayIso()) -> Settings {
        Settings(defaultStartMin: 465, defaultLunch: true, mileRate: 0.7, tuitionOn: true, tuitionRate: 1,
                 sickBalance: 0, sickAsOf: today)
    }

    public init(defaultStartMin: Int, defaultLunch: Bool, mileRate: Double, tuitionOn: Bool, tuitionRate: Double,
                sickBalance: Double, sickAsOf: ISODate) {
        self.defaultStartMin = defaultStartMin; self.defaultLunch = defaultLunch; self.mileRate = mileRate
        self.tuitionOn = tuitionOn; self.tuitionRate = tuitionRate; self.sickBalance = sickBalance; self.sickAsOf = sickAsOf
    }
}

public struct PrepayData: Sendable {
    public var days: [Day] = []
    public var stubs: [Stub] = []
    public var rates: [Rate] = []
    public var settings: Settings = .defaults()
    public var cashouts: [Cashout] = []
    public var tuition: [TuitionEvent] = []

    public init(days: [Day] = [], stubs: [Stub] = [], rates: [Rate] = [], settings: Settings = .defaults(),
                cashouts: [Cashout] = [], tuition: [TuitionEvent] = []) {
        self.days = days; self.stubs = stubs; self.rates = rates; self.settings = settings
        self.cashouts = cashouts; self.tuition = tuition
    }
}
