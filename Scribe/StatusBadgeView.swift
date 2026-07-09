import SwiftUI

/// Indicador de estado compacto: un punto de color más el texto de estado actual.
struct StatusBadgeView: View {
    let text: String
    let kind: StatusKind

    private var dotColor: Color {
        switch kind {
        case .neutral: return .green
        case .active: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var textColor: Color {
        kind == .error ? .red : .secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(dotColor.opacity(0.12))
        .clipShape(Capsule())
    }
}
