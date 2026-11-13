import SwiftUI
import UIKit

struct ContentView: View {
    @State private var tab: Int = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-openTab"), i + 1 < a.count {
            switch a[i + 1] {
            case "historial": return 1
            case "tendencias": return 2
            case "ajustes": return 3
            default: return 0
            }
        }
        return 0
    }()

    var body: some View {
        TabView(selection: $tab) {
            HoyView()
                .tabItem { Label("Hoy", systemImage: "sparkles") }
                .tag(0)
            HistorialView()
                .tabItem { Label("Historial", systemImage: "calendar") }
                .tag(1)
            TendenciasView()
                .tabItem { Label("Tendencias", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
    }
}

enum Theme {
    // Rojo exacto del icono de Adrián (#F2343E)
    static let accent = Color(red: 0.949, green: 0.204, blue: 0.243)
    static let bgGradient = LinearGradient(
        colors: [Color(red: 0.24, green: 0.07, blue: 0.12), Color(red: 0.086, green: 0.039, blue: 0.047)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/* Tarjeta de cristal: imitación de Liquid Glass que funciona desde iOS 15.
   En iOS 26, compilando con Xcode 26, los componentes del sistema (tab bar,
   hojas, controles) traen el material real; estas tarjetas mantienen el look. */
struct GlassCard<Content: View>: View {
    var radius: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.clear],
                                         startPoint: .topLeading, endPoint: .center))
                    .allowsHitTesting(false) // decorativo: sin esto se come los toques del contenido
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.07)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1)
                    .allowsHitTesting(false) // decorativo
            )
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.82)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: Theme.accent.opacity(0.45), radius: 12, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct GlassGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

extension View {
    func glassButton() -> some View { buttonStyle(GlassProminentButtonStyle()) }
    func glassGhostButton() -> some View { buttonStyle(GlassGhostButtonStyle()) }
}

struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: size * 0.09)
            if let s = score {
                Circle()
                    .trim(from: 0, to: CGFloat(s) / 100)
                    .stroke(ringColor(s), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(s)").font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            } else {
                Text("—").font(.system(size: size * 0.34, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
    private func ringColor(_ s: Int) -> Color {
        if s >= 80 { return Color(red: 0.55, green: 0.85, blue: 0.62) }
        if s >= 50 { return Color(red: 0.94, green: 0.65, blue: 0.35) }
        return Theme.accent
    }
}
