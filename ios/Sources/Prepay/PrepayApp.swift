import SwiftUI
import UIKit

@main
struct PrepayApp: App {
    @State private var model = AppModel()

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
            VStack(spacing: 16) {
                Text("Prepay").font(Theme.serif(44))
                ProgressView()
            }
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
            WorkDayView().tabItem { Label("Work day", systemImage: "clock") }.tag(AppModel.Tab.day)
            PayDayView().tabItem { Label("Pay day", systemImage: "dollarsign.circle") }.tag(AppModel.Tab.pay)
            HistoryView().tabItem { Label("History", systemImage: "list.bullet.rectangle") }.tag(AppModel.Tab.history)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppModel.Tab.settings)
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
