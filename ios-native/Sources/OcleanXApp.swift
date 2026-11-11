import SwiftUI

@main
struct OcleanXApp: App {
    @StateObject private var store = BrushStore()
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(ble)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { ble.attach(store: store) }
        }
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.302, blue: 0.404)      // #ff4d67
    static let cardBg = Color(red: 0.16, green: 0.08, blue: 0.10).opacity(0.72)
    static let cardBorder = Color.white.opacity(0.12)
    static let bgGradient = LinearGradient(
        colors: [Color(red: 0.24, green: 0.07, blue: 0.12), Color(red: 0.086, green: 0.039, blue: 0.047)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(Theme.cardBg)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder, lineWidth: 1))
    }
}
