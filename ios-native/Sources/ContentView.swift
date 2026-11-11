import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HoyView()
                .tabItem { Label("Hoy", systemImage: "sparkles") }
            HistorialView()
                .tabItem { Label("Historial", systemImage: "calendar") }
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
    }
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
