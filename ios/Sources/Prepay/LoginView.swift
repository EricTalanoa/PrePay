import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            BrandMark(size: 84)
            Text("Prepay").font(Theme.serif(48, weight: .semibold)).padding(.top, 24)
            Text("Know the check before it lands.")
                .font(Theme.serif(18)).italic()
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                feature("clock.fill", "Log each shift in seconds")
                feature("dollarsign.circle.fill", "See your next check before payday")
                feature("checkmark.seal.fill", "Catch tips that never made the stub")
            }
            .padding(.top, 36)

            Spacer()

            VStack(spacing: 12) {
                Button { Task { await model.signIn(.apple) } } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { Task { await model.signIn(.google) } } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink.opacity(0.18)))
                }
                .buttonStyle(.plain)
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 360)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: icon, size: 34)
            Text(text).font(.callout)
        }
    }
}
