import PrepayCore
import SwiftUI
import UIKit
import XCTest
@testable import Prepay

// Renders the main screens with made-up data for the README. Skipped unless
// SCREENSHOT_DIR is set; the Screenshots workflow sets it (as
// TEST_RUNNER_SCREENSHOT_DIR) and commits the PNGs to docs/screenshots.
final class Screenshots: XCTestCase {
    @MainActor
    func testCaptureScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for theme in ThemeChoice.allCases {
            try await shot("\(theme.rawValue)-login", theme, to: out) { _ in AnyView(LoginView()) }
            for (name, tab) in [("workday", AppModel.Tab.day), ("payday", .pay), ("history", .history), ("settings", .settings)] {
                try await shot("\(theme.rawValue)-\(name)", theme, to: out) { m in m.tab = tab; return AnyView(MainTabs()) }
            }
        }
        Theme.use(ThemeChoice.classic.rawValue)
    }

    @MainActor
    private func shot(_ name: String, _ theme: ThemeChoice, to out: URL, _ screen: (AppModel) -> AnyView) async throws {
        Theme.use(theme.rawValue)
        let model = AppModel()
        model.data = SampleData.make()
        model.email = "you@example.com"
        model.resetDraft()
        model.phase = .ready
        let root = screen(model)
            .environment(model)
            .tint(Theme.accent)
            .preferredColorScheme(Theme.current.scheme)

        // An iPhone 15/16-sized window, with room where the status bar and
        // home indicator would be.
        let size = CGSize(width: 393, height: 852)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = Theme.current.scheme == .dark ? .dark : .light
        let host = UIHostingController(rootView: root)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 54, left: 0, bottom: 34, right: 0)
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<6 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: ctx.cgContext)
            }
        }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("\(name).png"))
        window.isHidden = true
    }
}

/// About seven weeks of plausible shifts ending yesterday, a pay stub for each
/// of the last two checks, and the usual settings. Nobody's real pay.
enum SampleData {
    static func make() -> PrepayData {
        let today = todayIso()
        var days: [Day] = []
        for back in 1...50 {
            let date = addDays(today, -back)
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: dparse(date))
            if weekday == 1 || weekday == 7 || back % 9 == 4 { continue } // weekends and the odd day off
            let n = Double((back * 37) % 11)
            days.append(Day(
                date: date,
                startMin: back % 5 == 0 ? 420 : 465,
                endMin: 465 + 510 + (back * 23) % 120,
                lunch: back % 6 != 0,
                ccTips: 28 + n * 6.5,
                cashTips: back % 3 == 0 ? 20 + n * 2 : 0,
                travel: back % 13 == 0 ? .full : back % 8 == 0 ? .partial : .none,
                miles: back % 8 == 0 ? 42 : 0
            ))
        }
        let settings = Settings(defaultStartMin: 465, defaultLunch: true, mileRate: 0.7, tuitionOn: true, tuitionRate: 1,
                                sickBalance: 21.5, sickAsOf: addDays(today, -50))
        var data = PrepayData(days: days, rates: [Rate(effectiveFrom: "2000-01-01", rate: 24.5)], settings: settings)

        var p = prevPeriod(upcomingPeriod())
        for _ in 0..<2 {
            let t = estimate(data, p, today).totals
            data.stubs.append(Stub(periodStart: p.key, periodEnd: p.to, payDate: p.payDate,
                                   regHours: cents(t.reg), otHours: cents(t.ot), ccTips: cents(t.tips), bonus: t.perDiem,
                                   reimbursement: cents(t.tuition + t.milePay), tax: cents(t.tax), taxIsEstimate: false,
                                   cashTips: cents(t.cash)))
            data.tuition.append(TuitionEvent(periodStart: p.key, status: .received, amount: cents(t.tuition)))
            p = prevPeriod(p)
        }
        return data
    }
}
