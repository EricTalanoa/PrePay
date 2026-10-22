import SwiftUI
import UIKit

@main
struct PrepayApp: App {
    @State private var model = AppModel()

    init() { Theme.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { model.client.auth.handle($0) }
                .tint(Theme.accent)
                // The palette is light-only, like the site. Left to follow the
                // phone, Dark Mode turned system text white on the cream paper
                // and the forms and tab bar near-black.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .starting, .loading:
            VStack(spacing: 20) {
                BrandMark(size: 72)
                Text("Prepay").font(Theme.serif(40, weight: .semibold))
                ProgressView().tint(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
        case .signedOut:
            LoginView()
        case .ready:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            WorkDayView().tabItem { Label("Work day", systemImage: "clock.fill") }.tag(AppModel.Tab.day)
            PayDayView().tabItem { Label("Pay day", systemImage: "dollarsign.circle.fill") }.tag(AppModel.Tab.pay)
            HistoryView().tabItem { Label("History", systemImage: "list.bullet.rectangle.fill") }.tag(AppModel.Tab.history)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppModel.Tab.settings)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .alert("Couldn't save", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}

/// The app icon's P, drawn: a serif letter on an ink tile.
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Text("P")
            .font(Theme.serif(size * 0.62, weight: .semibold))
            .foregroundStyle(Theme.paper)
            .frame(width: size, height: size)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Theme.accent).frame(width: size * 0.16, height: size * 0.16).padding(size * 0.16)
            }
            .shadow(color: Theme.ink.opacity(0.18), radius: 14, y: 6)
            .accessibilityHidden(true)
    }
}
