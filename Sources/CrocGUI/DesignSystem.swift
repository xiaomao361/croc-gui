import SwiftUI

enum CrocPalette {
    static let canvas = Color.white
    static let chrome = Color(red: 0.965, green: 0.969, blue: 0.961)
    static let forest = Color(red: 0.122, green: 0.220, blue: 0.141)
    static let forestBright = Color(red: 0.157, green: 0.357, blue: 0.286)
    static let forestMuted = Color(red: 0.478, green: 0.780, blue: 0.522)
    static let cream = Color(red: 0.988, green: 0.980, blue: 0.929)
    static let ink = Color(red: 0.141, green: 0.243, blue: 0.184)
    static let olive = Color(red: 0.376, green: 0.420, blue: 0.380)
    static let danger = Color(red: 0.620, green: 0.200, blue: 0.161)
}

struct CodeGateMark: View {
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.12) {
            Capsule().frame(width: size * 0.16, height: size * 0.54)
            Circle().frame(width: size * 0.13)
            Circle().frame(width: size * 0.13)
            Circle().frame(width: size * 0.13)
            Capsule().frame(width: size * 0.16, height: size * 0.54)
        }
        .foregroundStyle(CrocPalette.forestBright)
        .frame(width: size * 1.35, height: size)
        .accessibilityHidden(true)
    }
}

enum CrocButtonKind: Equatable {
    case primary
    case success
    case secondary
    case destructive
    case destructiveFilled
    case mode(selected: Bool)
}

struct CrocButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: CrocButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor(configuration: configuration))
                    .shadow(
                        color: shadowColor,
                        radius: configuration.isPressed ? 1 : 3,
                        y: configuration.isPressed ? 0 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var cornerRadius: CGFloat {
        if case .mode = kind { return 8 }
        return 7
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .success, .destructiveFilled: .white
        case .secondary: CrocPalette.forest
        case .destructive: CrocPalette.danger
        case let .mode(selected): selected ? .white : CrocPalette.forest
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return configuration.isPressed ? CrocPalette.forest : CrocPalette.forestBright
        case .success:
            return configuration.isPressed ? CrocPalette.forestBright : CrocPalette.forest
        case .secondary:
            return configuration.isPressed ? CrocPalette.forest.opacity(0.12) : .white.opacity(0.82)
        case .destructive:
            return configuration.isPressed ? CrocPalette.danger.opacity(0.18) : CrocPalette.danger.opacity(0.08)
        case .destructiveFilled:
            return configuration.isPressed
                ? Color(red: 0.480, green: 0.118, blue: 0.094)
                : CrocPalette.danger
        case let .mode(selected):
            if selected {
                return configuration.isPressed ? CrocPalette.forest : CrocPalette.forestBright
            }
            return configuration.isPressed ? CrocPalette.forest.opacity(0.10) : .clear
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary, .success: CrocPalette.forest.opacity(0.35)
        case .secondary: CrocPalette.forest.opacity(0.18)
        case .destructive: CrocPalette.danger.opacity(0.22)
        case .destructiveFilled: Color.white.opacity(0.18)
        case let .mode(selected): selected ? .clear : CrocPalette.forest.opacity(0.10)
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary, .success, .destructiveFilled, .mode(selected: true): .black.opacity(0.05)
        default: .clear
        }
    }
}
