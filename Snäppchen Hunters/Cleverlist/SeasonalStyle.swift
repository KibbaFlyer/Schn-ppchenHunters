import SwiftUI

extension Theme {
    var surface: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.97), background], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var motifSymbol: String {
        switch self {
        case .summer: "sun.max.fill"
        case .winter: "snowflake"
        case .christmas: "sparkles"
        case .halloween: "moon.stars.fill"
        case .autumn: "leaf.fill"
        case .spring: "leaf.fill"
        }
    }
}

/// Static decorations stay behind controls and never intercept touches or VoiceOver.
struct SeasonalBackground: View {
    let theme: Theme

    // A fixed irregular scatter avoids a grid without jumping when the view redraws.
    private let positions: [CGPoint] = [
        CGPoint(x: 0.08, y: 0.07), CGPoint(x: 0.63, y: 0.03),
        CGPoint(x: 0.88, y: 0.16), CGPoint(x: 0.31, y: 0.21),
        CGPoint(x: 0.05, y: 0.34), CGPoint(x: 0.74, y: 0.30),
        CGPoint(x: 0.46, y: 0.41), CGPoint(x: 0.94, y: 0.48),
        CGPoint(x: 0.19, y: 0.53), CGPoint(x: 0.61, y: 0.60),
        CGPoint(x: 0.04, y: 0.72), CGPoint(x: 0.83, y: 0.69),
        CGPoint(x: 0.37, y: 0.78), CGPoint(x: 0.70, y: 0.88),
        CGPoint(x: 0.15, y: 0.94), CGPoint(x: 0.96, y: 0.97)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.background
                LinearGradient(colors: [theme.accent.opacity(0.20), .clear, theme.secondary.opacity(0.38)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(0..<positions.count, id: \.self) { index in
                    SeasonalMotif(theme: theme, variant: index % 3)
                        .frame(width: CGFloat(22 + (index * 7) % 17),
                               height: CGFloat(22 + (index * 7) % 17))
                        .rotationEffect(.degrees(Double((index * 53) % 140) - 70))
                        // White compositing only lightens the backdrop beneath text.
                        .opacity(index.isMultiple(of: 3) ? 0.40 : 0.28)
                        .position(x: geometry.size.width * positions[index].x,
                                  y: geometry.size.height * positions[index].y)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SeasonalMotif: View {
    let theme: Theme
    var variant = 0

    var body: some View {
        ZStack {
            if theme == .spring || (theme == .summer && variant == 1) {
                // Rounded petals are drawn as vectors, matching the playful seasonal artwork.
                ForEach(0..<5) { petal in
                    Ellipse().fill(.white)
                        .frame(width: 10, height: 18)
                        .offset(y: -9)
                        .rotationEffect(.degrees(Double(petal) * 72))
                }
                Circle().fill(.white).frame(width: 9, height: 9)
            } else if (theme == .halloween || theme == .christmas) && variant == 2 {
                Image(theme.artwork).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.white)
            } else {
                Image(systemName: theme.motifSymbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SeasonalScreen: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { SeasonalBackground(theme: theme) }
            .toolbarBackground(theme.background, for: .automatic)
            .tint(theme.accent)
    }
}
