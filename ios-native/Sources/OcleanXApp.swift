import SwiftUI
import UIKit

@main
struct OcleanXApp: App {
    @StateObject private var store = BrushStore()
    @StateObject private var ble = BLEManager()

    init() {
        // En iOS < 26 damos a la tab bar un material de cristal oscuro.
        // Compilando con Xcode 26, iOS 26 aplica Liquid Glass de serie y no
        // hace falta (y mejor no tocar) la apariencia personalizada.
        if #unavailable(iOS 26.0) {
            let a = UITabBarAppearance()
            a.configureWithTransparentBackground()
            a.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            a.backgroundColor = UIColor.black.withAlphaComponent(0.12)
            a.shadowColor = UIColor.white.withAlphaComponent(0.08)
            UITabBar.appearance().standardAppearance = a
            UITabBar.appearance().scrollEdgeAppearance = a
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(ble)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear {
                    ble.attach(store: store)
                    // Sincronización automática al abrir: si el cepillo ya se
                    // conectó alguna vez, reconecta por su identificador guardado
                    // sin escanear; si no, lo busca.
                    ble.sync()
                }
        }
    }
}
