import PrepayCore
import SwiftUI

struct WorkDayView: View {
    @Environment(AppModel.self) private var model
    @State private var saved = 0

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
                    VStack(alignment: .leading, spacing: 6) {
                        Caps(rate > 0 ? "\(String(format: "%g", (hours * 100).rounded() / 100)) h worked" : "Set your rate in Settings",
                             color: rate > 0 ? Theme.paper.opacity(0.65) : Theme.accentLight)
                        Text(money(subtotal))
                            .font(Theme.serif(44, weight: .semibold))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: subtotal)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("before tax · \(fmtFull(d.date))").font(.footnote).foregroundStyle(Theme.paper.opacity(0.65))
                    }
                    .foregroundStyle(Theme.paper)
                    .card(padding: 20, fill: Theme.ink, stroke: .clear)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    DatePicker(selection: Binding(
                        get: { dparse(model.draft.date) },
                        set: { model.draft.date = iso($0) }
                    ), displayedComponents: .date) { Label("Date", systemImage: "calendar") }
                    Picker("Entry", selection: $model.draft.mode) {
                        Text("Start / End").tag(Day.Mode.range)
                        Text("Total hours").tag(Day.Mode.total)
                    }
                    .pickerStyle(.segmented)
                }

                if d.mode == .range {
                    Section {
                        DatePicker(selection: minutesBinding({ model.draft.startMin }, { model.draft.startMin = $0 }),
                                   displayedComponents: .hourAndMinute) { Label("Clock in", systemImage: "arrow.right.circle") }
                        DatePicker(selection: minutesBinding({ model.draft.endMin }, { model.draft.endMin = $0 }),
                                   displayedComponents: .hourAndMinute) { Label("Clock out", systemImage: "arrow.left.circle") }
                        Toggle(isOn: $model.draft.lunch) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lunch taken")
                                    Text("30 min unpaid").font(.caption).foregroundStyle(Theme.muted)
                                }
                            } icon: { Image(systemName: "fork.knife") }
                        }
                    } header: { Text("Shift") }
                } else {
                    Section {
                        HStack {
                            Label("Hours worked", systemImage: "hourglass")
                            Spacer()
                            DecimalField(placeholder: "0.00", value: Binding(
                                get: { model.draft.totalHours ?? 0 }, set: { model.draft.totalHours = $0 }))
                        }
                    } header: { Text("Shift") }
                }

                Section("Tips") {
                    MoneyField(title: "Credit card tips", icon: "creditcard", value: $model.draft.ccTips)
                    MoneyField(title: "Cash tips", note: "tracked only — not on your check", icon: "banknote", value: $model.draft.cashTips)
                }

                Section("Long distance") {
                    Picker("Travel", selection: $model.draft.travel) {
                        Text("Local").tag(Travel.none)
                        Text("Travel \(money(perDiem(.partial)))").tag(Travel.partial)
                        Text("Away \(money(perDiem(.full)))").tag(Travel.full)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("POV miles driven")
                                Text(d.miles > 0 ? "\(money(d.miles * mileRate)) at $\(String(format: "%.2f", mileRate))/mi" : "Reimbursed, not taxed")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        } icon: { Image(systemName: "car") }
                        Spacer()
                        DecimalField(placeholder: "0", value: $model.draft.miles, width: 90)
                    }
                }

                Section {
                    VStack(spacing: 10) {
                        Button {
                            model.saveDraft()
                            saved += 1
                        } label: {
                            Label(model.editing ? "Update day" : "Record day",
                                  systemImage: model.editing ? "checkmark.circle.fill" : "plus.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(color: model.editing ? Theme.ink : Theme.accent))
                        if model.editing {
                            HStack(spacing: 10) {
                                Button("Cancel edit") { model.resetDraft() }
                                    .buttonStyle(.bordered).tint(Theme.muted)
                                Button("Delete", role: .destructive) { model.deleteDraft() }
                                    .buttonStyle(.bordered).tint(Theme.accent)
                            }
                            .controlSize(.large)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .paperBackground()
            .navigationTitle(model.editing ? "Edit day" : "Work day")
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
    var icon = "dollarsign.circle"
    @Binding var value: Double

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let note { Text(note).font(.caption).foregroundStyle(Theme.muted) }
                }
            } icon: { Image(systemName: icon) }
            Spacer()
            DecimalField(placeholder: "0.00", value: $value, width: 120, size: 20)
        }
    }
}
