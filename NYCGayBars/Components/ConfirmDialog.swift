import SwiftUI

/// A custom confirmation dialog styled to match the app (glass card on a dimmed
/// backdrop) instead of the plain system action sheet.
struct ConfirmDialog: View {
    struct Action: Identifiable {
        enum Style { case destructive, primary, cancel }
        let id = UUID()
        let label: String
        let style: Style
        let handler: () -> Void
    }

    let title: String
    let message: String
    let actions: [Action]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.gray400)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button {
                            onDismiss()
                            action.handler()
                        } label: {
                            Text(action.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(foreground(action.style))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(fill(action.style)))
                                .overlay(Capsule().strokeBorder(border(action.style), lineWidth: 1))
                        }
                        .buttonStyle(PressableScale())
                    }
                }
                .padding(.top, 20)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .glassSurface(radius: 28, bordered: true)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    private func foreground(_ s: Action.Style) -> Color {
        switch s {
        case .destructive: return Palette.red
        case .primary: return Palette.primary
        case .cancel: return Palette.gray300
        }
    }
    private func fill(_ s: Action.Style) -> Color {
        switch s {
        case .destructive: return Palette.red.opacity(0.15)
        case .primary: return Palette.primary.opacity(0.15)
        case .cancel: return Color.white.opacity(0.08)
        }
    }
    private func border(_ s: Action.Style) -> Color {
        switch s {
        case .destructive: return Palette.red.opacity(0.4)
        case .primary: return Palette.primary.opacity(0.4)
        case .cancel: return Color.white.opacity(0.12)
        }
    }
}
