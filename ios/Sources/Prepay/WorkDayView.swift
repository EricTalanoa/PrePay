import PrepayCore
import SwiftUI

struct WorkDayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let d = model.draft
        let rate = rateFor(model.data.rates, d.date)
        let hours = dayHours(d)
        let mileRate = model.data.settings.mileRate
        let subtotal = hours * rate + d.ccTips + perDiem(d.travel) + d.miles * mileRate

        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: Binding(
                        get: { dparse(model.draft.date) },
                        set: { model.draft.date = iso($0) }
                    ), displayedComponents: .date)
                    Picker("Entry", selection: $model.draft.mode) {
                        Text("Start / End").tag(Day.Mode.range)
                        Text("Total hours").tag(Day.Mode.total)
                    }
                    .pickerStyle(.segmented)
                }

                if d.mode == .range {
                    Section {
                        DatePicker("Clock in", selection: minutesBinding({ model.draft.startMin }, { model.draft.startMin = $0 }),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Clock out", selection: minutesBinding({ model.draft.endMin }, { model.draft.endMin = $0 }),
                                   displayedComponents: .hourAndMinute)
                        Toggle("Lunch taken (30 min unpaid)", isOn: $model.draft.lunch)
                    }
                } else {
                    Section {
                        HStack {
                            Text("Hours worked")
                            Spacer()
                            DecimalField(placeholder: "0.00", value: Binding(
                                get: { model.draft.totalHours ?? 0 }, set: { model.draft.totalHours = $0 }))
                        }
                    }
                }

                Section {
                    MoneyField(title: "Credit card tips", value: $model.draft.ccTips)
                    MoneyField(title: "Cash tips", note: "tracked only — not on your check", value: $model.draft.cashTips)
                }

                Section("Long distance") {
                    Picker("Travel", selection: $model.draft.travel) {
                        Text("Local").tag(Travel.none)
                        Text("Travel \(money(perDiem(.partial)))").tag(Travel.partial)
                        Text("Away \(money(perDiem(.full)))").tag(Travel.full)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("POV miles driven")
                            Caps(d.miles > 0 ? "\(money(d.miles * mileRate)) at $\(String(format: "%.2f", mileRate))/mi" : "Reimbursed, not taxed")
                        }
                        Spacer()
                        DecimalField(placeholder: "0", value: $model.draft.miles, width: 90)
                    }
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Caps(rate > 0 ? "\(String(format: "%g", (hours * 100).rounded() / 100)) h worked" : "Set your rate in Settings")
                        Spacer()
                        Text(money(subtotal)).font(Theme.serif(28))
                    }
                    Button(model.editing ? "Update day" : "Record day") { model.saveDraft() }
                        .frame(maxWidth: .infinity).fontWeight(.semibold)
                    if model.editing {
                        Button("Delete", role: .destructive) { model.deleteDraft() }.frame(maxWidth: .infinity)
                        Button("Cancel edit") { model.resetDraft() }.frame(maxWidth: .infinity).foregroundStyle(Theme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Work day")
        }
        .onChange(of: model.tab) { _, tab in
            // clock-out tracks "now" whenever a new day is opened, never mid-edit
            if tab == .day && !model.editing { model.draft.endMin = AppModel.endNow(model.draft.startMin) }
        }
    }
}

struct MoneyField: View {
    let title: String
    var note: String? = nil
    @Binding var value: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
            DecimalField(placeholder: "0.00", value: $value, width: 120, size: 20)
        }
    }
}
