import SwiftUI

// The web app's palette: warm paper, near-black ink, a brick-red accent.
enum Theme {
    static let paper = Color(red: 0.957, green: 0.949, blue: 0.925)
    static let card = Color(red: 0.992, green: 0.988, blue: 0.976)
    static let ink = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let muted = Color(red: 0.46, green: 0.44, blue: 0.42)
    static let accent = Color(red: 0.80, green: 0.27, blue: 0.20)
    static let good = Color(red: 0.36, green: 0.52, blue: 0.40)

    static func serif(_ size: CGFloat) -> Font { .system(size: size, design: .serif) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

/// The small spaced caps used for section labels.
struct Caps: View {
    let text: String
    var color: Color = Theme.muted
    init(_ text: String, color: Color = Theme.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Theme.mono(10)).tracking(1.6).foregroundStyle(color)
    }
}

struct LineRow: View {
    let name: String
    var detail: String? = nil
    let amount: String
    var bold = false
    var dim = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).fontWeight(bold ? .bold : .regular)
            if let detail { Text(detail).font(Theme.mono(12)).foregroundStyle(Theme.muted) }
            Spacer()
            Text(amount).font(Theme.mono(15, weight: bold ? .bold : .regular))
        }
        .foregroundStyle(dim ? Theme.muted : Theme.ink)
        .padding(.vertical, 6)
    }
}

/// Minutes after midnight <-> a Date today, for the hour-and-minute pickers.
func minutesBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
    Binding(
        get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(get() * 60)) },
        set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            set((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
    )
}

/// A number box that updates its value on every keystroke. The decimal pad
/// has no return key, so waiting for "submit" would lose what was typed.
struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double
    var width: CGFloat = 110
    var size: CGFloat = 17
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(Theme.mono(size)).frame(width: width)
            .onAppear { text = value == 0 ? "" : String(format: "%g", value) }
            .onChange(of: text) { _, t in value = Double(t) ?? 0 }
            .onChange(of: value) { _, v in if (Double(text) ?? 0) != v { text = v == 0 ? "" : String(format: "%g", v) } }
    }
}
