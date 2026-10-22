import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Text("Prepay").font(Theme.serif(48))
            Rectangle().fill(Theme.ink).frame(width: 44, height: 1)
            Text("Know the check before it lands.").foregroundStyle(Theme.muted)
            VStack(spacing: 10) {
                Button { Task { await model.signIn(.apple) } } label: {
                    Label("Continue with Apple", systemImage: "apple.logo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.ink)
                Button { Task { await model.signIn(.google) } } label: {
                    Label("Continue with Google", systemImage: "g.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.ink)
            }
            .controlSize(.large)
            .frame(maxWidth: 300)
            if let error = model.error {
                Text(error).font(Theme.mono(11)).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }
}
