import PrepayCore
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = computeStats(model.data.days, model.data.rates, todayIso())
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        ScrollView {
            if s.daysWorked == 0 {
                ContentUnavailableView("No stats yet", systemImage: "chart.bar.xaxis",
                                       description: Text("Log a few days and the stats show up here."))
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Caps("Records").padding(.horizontal, 4)
                    LazyVGrid(columns: cols, spacing: 12) {
                        tile("Highest earning day", s.highestDay.map { money($0.value) }, on(s.highestDay))
                        tile("Lowest earning day", s.lowestDay.map { money($0.value) }, on(s.lowestDay))
                        tile("Longest day", s.longestDay.map { hrs($0.value) }, on(s.longestDay))
                        tile("Shortest day", s.shortestDay.map { hrs($0.value) }, on(s.shortestDay))
                        tile("Most cash in a day", s.mostCash.map { money($0.value) }, on(s.mostCash))
                        tile("Most CC tips in a day", s.mostCcTips.map { money($0.value) }, on(s.mostCcTips))
                        tile("Most days in a row", s.longestStreak.map { days($0.days) }, run(s.longestStreak))
                        tile("Most days off in a row", s.longestBreak.map { days($0.days) }, run(s.longestBreak))
                        tile("Current streak", days(s.currentStreak), s.currentStreak > 0 ? "and counting" : "not working today")
                        tile("Best week", s.bestWeek.map { money($0.value) }, s.bestWeek.map { "week of \(fmtMD($0.date))" })
                        tile("Earliest clock-in", s.earliestStart?.label, s.earliestStart.map { fmtFull($0.date) })
                        tile("Latest clock-out", s.latestEnd?.label, s.latestEnd.map { fmtFull($0.date) })
                        tile("Most miles in a day", s.mostMiles.map { "\(String(format: "%g", $0.value)) mi" }, on(s.mostMiles))
                        tile("Busiest weekday", s.busiestWeekday?.name, s.busiestWeekday.map { "\(days($0.count)) worked" })
                    }

                    Caps("All time").padding(.horizontal, 4).padding(.top, 10)
                    LazyVGrid(columns: cols, spacing: 12) {
                        tile("Days worked", "\(s.daysWorked)", "\(hrs(s.totalHours)) total")
                        tile("Avg per hour", money(s.avgHourly), "wages + all tips")
                        tile("Earned", money(s.totalEarned), "before tax")
                        tile("CC tips", money(s.totalCcTips), nil)
                        tile("Cash tips", money(s.totalCash), nil)
                        tile("Per-diem", money(s.totalPerDiem), "\(days(s.travelDays)) on the road")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Theme.paper)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ label: String, _ value: String?, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Caps(label).lineLimit(1).minimumScaleFactor(0.75)
            Text(value ?? "—").font(Theme.serif(24, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub ?? " ").font(Theme.mono(11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .card(padding: 14)
    }

    private func on(_ x: DayStat?) -> String? { x.map { fmtFull($0.date) } }
    private func run(_ r: Run?) -> String? { r.map { $0.days == 1 ? fmtMD($0.from) : "\(fmtMD($0.from)) – \(fmtMD($0.to))" } }
    private func hrs(_ x: Double) -> String { "\(String(format: "%g", (x * 100).rounded() / 100))h" }
    private func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }
}
