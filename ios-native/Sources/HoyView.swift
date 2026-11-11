import SwiftUI

struct HoyView: View {
    @EnvironmentObject var store: BrushStore
    @EnvironmentObject var ble: BLEManager
    @State private var selected: BrushSession? = nil

    private var todaySessions: [BrushSession] { store.sessionsOn(Date()) }
    private var shown: BrushSession? { selected ?? todaySessions.first }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Oclean").font(.largeTitle.bold()).padding(.top, 8)

                    // Cepillo: imagen + batería + cabezal
                    GlassCard {
                        HStack(spacing: 18) {
                            if let url = Bundle.main.url(forResource: "brush", withExtension: "png", subdirectory: "web/assets"),
                               let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img).resizable().scaledToFit()
                                    .frame(width: 74, height: 150)
                                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, x: 0, y: 6)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("BATERÍA").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                                BatteryBar(value: store.battery)
                                Text("CABEZAL").font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.top, 2)
                                Text(headText).font(.headline)
                            }
                            Spacer()
                        }
                    }

                    // Sincronizar
                    Button(action: { ble.sync() }) {
                        HStack(spacing: 8) {
                            if ble.statusBusy { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.triangle.2.circlepath") }
                            Text(ble.statusBusy ? "Conectando…" : "Sincronizar")
                        }
                    }
                    .glassButton()
                    .disabled(ble.connecting)

                    HStack(spacing: 6) {
                        Circle().fill(ble.statusBusy ? Color.orange : (store.battery != nil ? Color.green : Color.gray))
                            .frame(width: 8, height: 8)
                        Text(ble.status).foregroundColor(.secondary).font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if !store.pending.isEmpty {
                        Text("⚙️ Cambios de ajustes pendientes: se enviarán al sincronizar.")
                            .font(.footnote).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if ble.offerScanAll {
                        if ble.candidates.isEmpty {
                            Text("No se vio ningún dispositivo Bluetooth cerca. Despierta el cepillo y reintenta.")
                                .font(.footnote).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Elige tu cepillo").font(.headline)
                                    ForEach(ble.candidates) { c in
                                        Button(action: { ble.connectCandidate(c) }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "wave.3.right")
                                                Text(c.name)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.caption)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Cepillados de hoy
                    Text("CEPILLADOS DE HOY").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    if !todaySessions.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(todaySessions) { s in
                                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = s } }) {
                                    VStack(spacing: 2) {
                                        Text(fmtTime(s.ts)).fontWeight(.semibold)
                                        Text(s.score.map { "\($0)" } ?? "—").font(.subheadline)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill((shown?.ts == s.ts) ? Theme.accent.opacity(0.55) : Color.white.opacity(0.07))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1).allowsHitTesting(false))

                        if let s = shown {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 14) {
                                        ScoreRing(score: s.score, size: 64)
                                        VStack(alignment: .leading, spacing: 4) {
                                            if s.sample == true {
                                                Text("Ejemplo").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Color.white.opacity(0.12)).cornerRadius(6)
                                            }
                                            Text(schemeName(s.pnum)).font(.headline)
                                            Text(fmtTime(s.ts)).foregroundColor(.secondary).font(.subheadline)
                                            Text("⏱ \(fmtDur(s.dur)) · Cobertura \(s.coverage.map { "\($0)%" } ?? "—")")
                                                .foregroundColor(.secondary).font(.subheadline)
                                        }
                                        Spacer()
                                    }
                                    if let zc = zoneClasses(s) {
                                        DentureView(classes: zc)
                                            .frame(height: 340)
                                            .cornerRadius(14)
                                    } else {
                                        Text("Sin datos de zonas").foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                                    }
                                }
                            }
                        }
                    } else if store.lastSync != nil && store.lastSess == 0 {
                        emptyCard("No había sesiones nuevas en el cepillo.\nEs normal: si la app oficial de Oclean se conectó antes, descargó el historial ella.\nCepíllate y sincroniza de nuevo aquí.")
                    } else {
                        emptyCard("Aún no hay cepillados hoy.\nConecta el cepillo para descargar tu historial.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Solo capturas del simulador: mostrar una sesión con zonas mal cepilladas.
            let a = ProcessInfo.processInfo.arguments
            if a.contains("-hoySelectBad"), selected == nil,
               let bad = todaySessions.first(where: { (zoneClasses($0) ?? []).contains(.bad) }) {
                selected = bad
            }
        }
    }

    private var headText: String {
        if let hd = store.headDays {
            let left = max(0, hd - (store.headTimes ?? 0))
            return "quedan \(left) días"
        }
        return "—"
    }

    private func emptyCard(_ text: String) -> some View {
        GlassCard {
            VStack(spacing: 10) {
                Text("🦷").font(.largeTitle)
                Text(text).multilineTextAlignment(.center).foregroundColor(.secondary).font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct BatteryBar: View {
    let value: Int?
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(value ?? 0) / 100)
                }
            }
            .frame(height: 12)
            Text(value.map { "\($0)%" } ?? "—").font(.headline)
        }
    }
    private var barColor: Color {
        guard let v = value else { return Color.white.opacity(0.2) }
        if v <= 20 { return Color(red: 1, green: 0.27, blue: 0.23) }
        if v <= 50 { return Color.orange }
        return Theme.accent
    }
}
