import SwiftUI
import UIKit

/// One look for the whole app. Colors are named for their job, not their hue,
/// so a dark theme can put light text on a dark page.
struct Palette: Sendable {
    var paper: Color      // the page behind everything
    var card: Color       // raised cards and the tab bar
    var ink: Color        // body text
    var muted: Color      // secondary text
    var accent: Color     // tint, warnings, highlights
    var good: Color       // cash already in hand
    var hero: Color       // the big summary cards
    var onHero: Color     // text on those cards
    var heroAccent: Color // highlights on those cards
    var heroStroke: Color
    var glow: Color       // light thrown by the hero cards
    var button: Color     // primary buttons and selected segments
    var onButton: Color
    var shadow: Color
    var scheme: ColorScheme

    // The web app's palette: warm paper, near-black ink, a brick-red accent.
    static let classic: Palette = {
        let ink = Color(red: 0.165, green: 0.149, blue: 0.133)
        let paper = Color(red: 0.957, green: 0.949, blue: 0.925)
        return Palette(
            paper: paper,
            card: Color(red: 0.992, green: 0.988, blue: 0.976),
            ink: ink,
            muted: Color(red: 0.46, green: 0.44, blue: 0.42),
            accent: Color(red: 0.80, green: 0.27, blue: 0.20),
            good: Color(red: 0.36, green: 0.52, blue: 0.40),
            hero: ink, onHero: paper,
            heroAccent: Color(red: 0.96, green: 0.58, blue: 0.48),
            heroStroke: .clear, glow: .clear,
            button: ink, onButton: paper,
            shadow: ink.opacity(0.06),
            scheme: .light
        )
    }()

    // From the firehouse icon: a near-black badge lit in gold, with flame
    // orange and red at the edges.
    static let firehouse: Palette = {
        let gold = Color(red: 0.98, green: 0.80, blue: 0.33)
        return Palette(
            paper: Color(red: 0.067, green: 0.075, blue: 0.086),
            card: Color(red: 0.110, green: 0.118, blue: 0.133),
            ink: Color(red: 0.965, green: 0.933, blue: 0.875),
            muted: Color(red: 0.62, green: 0.60, blue: 0.57),
            accent: Color(red: 1.00, green: 0.45, blue: 0.20),
            good: Color(red: 0.49, green: 0.77, blue: 0.50),
            hero: Color(red: 0.090, green: 0.086, blue: 0.094),
            onHero: gold,
            heroAccent: Color(red: 1.00, green: 0.47, blue: 0.26),
            heroStroke: gold.opacity(0.55),
            glow: Color(red: 1.00, green: 0.55, blue: 0.15).opacity(0.35),
            button: gold, onButton: Color(red: 0.08, green: 0.07, blue: 0.06),
            shadow: .black.opacity(0.45),
            scheme: .dark
        )
    }()
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case classic, firehouse

    static let key = "theme"
    var id: String { rawValue }
    var name: String { self == .classic ? "Classic" : "Firehouse" }
    var palette: Palette { self == .classic ? .classic : .firehouse }
}

enum Theme {
    /// Set from the stored choice before any view draws, and changed only by
    /// `use(_:)` on the main thread, which also rebuilds the views.
    nonisolated(unsafe) private(set) static var current =
        (ThemeChoice(rawValue: UserDefaults.standard.string(forKey: ThemeChoice.key) ?? "") ?? .classic).palette
    nonisolated(unsafe) private static var applied: String?

    static var paper: Color { current.paper }
    static var card: Color { current.card }
    static var ink: Color { current.ink }
    static var muted: Color { current.muted }
    static var accent: Color { current.accent }
    static var good: Color { current.good }
    static var hero: Color { current.hero }
    static var onHero: Color { current.onHero }
    static var heroAccent: Color { current.heroAccent }
    static var button: Color { current.button }
    static var onButton: Color { current.onButton }
    static var line: Color { current.ink.opacity(0.10) }
    static let radius: CGFloat = 18

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    /// Switches to the stored theme if it isn't the one in use. Cheap to call
    /// on every render.
    @MainActor static func use(_ raw: String) {
        guard raw != applied else { return }
        applied = raw
        current = (ThemeChoice(rawValue: raw) ?? .classic).palette
        applyAppearance()
    }

    /// The UIKit chrome SwiftUI doesn't style: serif bar titles on paper, a
    /// cream tab bar, and ink segmented controls.
    @MainActor private static func applyAppearance() {
        let ink = UIColor(Theme.ink)
        func serif(_ size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.paper)
        nav.shadowColor = UIColor(Theme.line)
        nav.largeTitleTextAttributes = [.font: serif(32), .foregroundColor: ink]
        nav.titleTextAttributes = [.font: serif(17), .foregroundColor: ink]
        let edge = nav.copy()
        edge.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.card)
        tab.shadowColor = UIColor(Theme.line)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(Theme.button)
        seg.backgroundColor = UIColor(Theme.paper)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(Theme.onButton), .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
    }
}

/// A raised cream card on the paper background.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = Theme.card
    var stroke: Color = Theme.line
    var glow: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(stroke))
            .shadow(color: Theme.current.shadow, radius: 12, y: 4)
            .shadow(color: glow, radius: 18)
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = Theme.card, stroke: Color = Theme.line) -> some View {
        modifier(CardStyle(padding: padding, fill: fill, stroke: stroke))
    }

    /// The big summary card at the top of a screen; pair with `Theme.onHero` text.
    func heroCard(padding: CGFloat = 20) -> some View {
        foregroundStyle(Theme.onHero)
            .modifier(CardStyle(padding: padding, fill: Theme.hero, stroke: Theme.current.heroStroke, glow: Theme.current.glow))
    }

    /// Paper behind a Form or List, with cream rows.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.paper)
    }
}

/// A full-width filled button for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.button

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            // dark text on the bright buttons of a dark theme
            .foregroundStyle(color == Theme.button || Theme.current.scheme == .dark ? Theme.onButton : .white)
            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A small capsule tag, e.g. ACTUAL / ESTIMATE.
struct Pill: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased()).font(Theme.mono(9, weight: .semibold)).tracking(1.0)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// A tinted rounded square holding an SF Symbol, like Settings uses.
struct IconBadge: View {
    let systemImage: String
    var color: Color = Theme.accent
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
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
