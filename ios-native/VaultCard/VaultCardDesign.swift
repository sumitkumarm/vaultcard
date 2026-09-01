import SwiftUI

enum VaultTheme {
    static let electricBlue = Color(red: 0.05, green: 0.46, blue: 1.0)
    static let deepBlue = Color(red: 0.02, green: 0.18, blue: 0.48)
    static let midnight = Color(red: 0.0, green: 0.055, blue: 0.13)
    static let navy = Color(red: 0.0, green: 0.11, blue: 0.24)
    static let success = Color(red: 0.18, green: 0.72, blue: 0.34)
    static let warning = Color(red: 1.0, green: 0.63, blue: 0.08)
    static let danger = Color(red: 0.96, green: 0.24, blue: 0.30)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? midnight : Color(red: 0.965, green: 0.977, blue: 1.0)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.92)
    }

    static func elevatedSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.14, blue: 0.26) : Color.white
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.cyan.opacity(0.18) : electricBlue.opacity(0.14)
    }
}

struct VaultBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VaultTheme.canvas(for: colorScheme)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [VaultTheme.navy.opacity(0.92), VaultTheme.midnight, .black.opacity(0.25)]
                    : [Color.white, Color(red: 0.91, green: 0.95, blue: 1.0), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [VaultTheme.electricBlue.opacity(colorScheme == .dark ? 0.25 : 0.11), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct VaultSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16

    init(cornerRadius: CGFloat = 22, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(VaultTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VaultTheme.border(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: colorScheme == .dark ? .black.opacity(0.16) : VaultTheme.deepBlue.opacity(0.07), radius: 10, y: 4)
    }
}

extension View {
    @ViewBuilder
    func vaultGlass(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func vaultPrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

struct VaultBrandMark: View {
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.58, blue: 1.0), Color(red: 0.02, green: 0.16, blue: 0.57)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color.cyan.opacity(0.75), lineWidth: 1.4)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white, Color.cyan.opacity(0.7))
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: VaultTheme.electricBlue.opacity(0.36), radius: 24)
        .accessibilityHidden(true)
    }
}

struct VaultStatusPill: View {
    let title: String
    var active = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? VaultTheme.electricBlue : Color.secondary.opacity(0.1), in: Capsule())
    }
}

struct VaultNetworkMark: View {
    let network: CardNetwork

    var body: some View {
        Group {
            switch network {
            case .visa:
                Text("VISA").italic()
            case .mastercard:
                HStack(spacing: -7) {
                    Circle().fill(Color.red).frame(width: 22, height: 22)
                    Circle().fill(Color.orange).frame(width: 22, height: 22)
                }
            case .unknown:
                Image(systemName: "creditcard")
            }
        }
        .font(.headline.weight(.black))
        .foregroundStyle(.white)
        .accessibilityLabel(network.displayName)
    }
}

struct VaultCardArtwork: View {
    let card: VaultCard
    var compact = false
    var revealedCardNumber: String? = nil
    var emphasizesEdge = false

    private var gradient: [Color] {
        let palette: [[Color]] = [
            [Color(red: 0.08, green: 0.36, blue: 0.66), Color(red: 0.02, green: 0.11, blue: 0.29)],
            [Color(red: 0.06, green: 0.43, blue: 0.47), Color(red: 0.01, green: 0.16, blue: 0.24)],
            [Color(red: 0.31, green: 0.25, blue: 0.57), Color(red: 0.10, green: 0.07, blue: 0.29)],
            [Color(red: 0.46, green: 0.18, blue: 0.34), Color(red: 0.20, green: 0.05, blue: 0.16)],
            [Color(red: 0.08, green: 0.35, blue: 0.27), Color(red: 0.01, green: 0.15, blue: 0.12)],
            [Color(red: 0.15, green: 0.28, blue: 0.47), Color(red: 0.04, green: 0.10, blue: 0.23)],
            [Color(red: 0.35, green: 0.27, blue: 0.17), Color(red: 0.16, green: 0.10, blue: 0.06)],
            [Color(red: 0.28, green: 0.34, blue: 0.43), Color(red: 0.07, green: 0.10, blue: 0.16)]
        ]
        let seed = (card.id + card.last4).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 10_000 }
        let index = seed % palette.count
        return palette[index % palette.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(Color.white.opacity(0.09))
                .frame(width: compact ? 120 : 210)
                .offset(x: compact ? 80 : 140, y: compact ? -34 : -58)
            LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                .rotationEffect(.degrees(-20))
                .offset(x: -50)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous))
            VStack(alignment: .leading, spacing: compact ? 7 : 13) {
                HStack(alignment: .top) {
                    Text(card.displayName)
                        .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    VaultNetworkMark(network: card.network)
                }
                Spacer(minLength: 0)
                Text(revealedCardNumber.map(CardRules.formatCardNumber) ?? "••••  \(card.last4)")
                    .font(.system(compact ? .caption : .body, design: .monospaced, weight: .medium))
                HStack {
                    if !compact {
                        Text(card.balance?.formatted(.currency(code: "USD")) ?? "Balance unavailable")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer()
                    Text(card.balanceFreshness() == .upToDate ? "Up to date" : "Needs refresh")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(card.balanceFreshness() == .upToDate ? VaultTheme.success : VaultTheme.warning)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.2), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(compact ? 13 : 18)
        }
        .frame(height: compact ? 92 : 176)
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 16 : 24, style: .continuous)
                .stroke(.white.opacity(emphasizesEdge ? 0.48 : 0.24), lineWidth: emphasizesEdge ? 1.4 : 1)
        }
        .shadow(color: gradient.first?.opacity(0.2) ?? .clear, radius: 12, y: 6)
    }
}

struct VaultFloatingBar: View {
    let vaultSelected: Bool
    let addSelected: Bool
    let settingsSelected: Bool
    let showVault: () -> Void
    let addCard: () -> Void
    let showSettings: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 16) {
                    barContent
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            } else {
                barContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 1) }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }

    private var barContent: some View {
        HStack(spacing: 34) {
            Button(action: showVault) {
                Label("Vault", systemImage: "rectangle.stack.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("tray.vault")
            .disabled(vaultSelected)
            .foregroundStyle(vaultSelected ? VaultTheme.electricBlue : .primary)
            Button(action: addCard) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(addSelected ? Color.secondary : VaultTheme.electricBlue, in: Circle())
                    .shadow(color: addSelected ? .clear : VaultTheme.electricBlue.opacity(0.4), radius: 14)
            }
            .accessibilityLabel("Add Card")
            .accessibilityIdentifier("cards.add")
            .disabled(addSelected)
            Button(action: showSettings) {
                Label("Settings", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("tray.settings")
            .disabled(settingsSelected)
            .foregroundStyle(settingsSelected ? VaultTheme.electricBlue : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct VaultRowIcon: View {
    let symbol: String
    var color = VaultTheme.electricBlue

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
