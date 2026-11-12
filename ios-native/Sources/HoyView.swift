import SwiftUI

struct HoyView: View {
    @EnvironmentObject var store: BrushStore
    @EnvironmentObject var ble: BLEManager
    @State private var selected: BrushSession? = nil

    private var todaySessions: [BrushSession] { store.sessionsOn(Date()) }
    private var shown: BrushSession? { selected ?? todaySessions.first }

    /* Pantalla Hoy SIN scroll vertical (petición de Adrián): todo visible de un
       vistazo. El 3D es la pieza flexible: absorbe el alto que sobre. */
    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                // Cabecera: solo el título
                Text("Oclean").font(.title.bold())
                    .padding(.top, 2)

                // Cepillo: imagen + batería + cabezal + estado de sincronización
                // (el punto y el texto viven dentro de esta tarjeta, petición de Adrián)
                GlassCard {
                    HStack(spacing: 14) {
                        if let url = Bundle.main.url(forResource: "brush", withExtension: "png", subdirectory: "web/assets"),
                           let img = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: img).resizable().scaledToFit()
                                .frame(width: 46, height: 92)
                                .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text("BATERÍA").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                                BatteryBar(value: store.battery)
                            }
                            HStack(spacing: 8) {
                                Text("CABEZAL").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                                Text(headText).font(.subheadline.weight(.medium))
                            }
                            HStack(alignment: .center, spacing: 6) {
                                Circle().fill(ble.statusBusy ? Color.orange : (store.battery != nil ? Color.green : Color.gray))
                                    .frame(width: 7, height: 7)
                                Text(ble.status).font(.caption2).foregroundColor(.secondary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                // Sincronizar
                Button(action: { ble.sync() }) {
                    HStack(spacing: 7) {
                        if ble.statusBusy { ProgressView().tint(.white).scaleEffect(0.85) }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                        Text(ble.statusBusy ? "Conectando…" : "Sincronizar")
                    }
                }
                .glassButton()
                .disabled(ble.connecting)

                if !store.pending.isEmpty {
                    Text("⚙️ Cambios de ajustes pendientes: se enviarán al sincronizar.")
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if ble.offerScanAll {
                    if ble.candidates.isEmpty {
                        Text("No se vio ningún dispositivo Bluetooth cerca. Despierta el cepillo y reintenta.")
                            .font(.caption2).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Elige tu cepillo").font(.subheadline.weight(.semibold))
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(ble.candidates) { c in
                                            Button(action: { ble.connectCandidate(c) }) {
                                                HStack(spacing: 10) {
                                                    Image(systemName: "wave.3.right")
                                                    Text(c.name)
                                                    Spacer()
                                                    Image(systemName: "chevron.right").font(.caption)
                                                }
                                                .foregroundColor(.white)
                                                .padding(.vertical, 5)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxHeight: 120)
                            }
                        }
                    }
                }

                // Cepillados de hoy
                Text("CEPILLADOS DE HOY").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                if !todaySessions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(todaySessions) { s in
                            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = s } }) {
                                VStack(spacing: 1) {
                                    Text(fmtTime(s.ts)).font(.subheadline.weight(.semibold))
                                    Text(s.score.map { "\($0)" } ?? "—").font(.caption)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill((shown?.ts == s.ts) ? Theme.accent.opacity(0.55) : Color.white.opacity(0.07))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1).allowsHitTesting(false))

                    if let s = shown {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    ScoreRing(score: s.score, size: 46)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(schemeName(s.pnum)).font(.subheadline.weight(.semibold))
                                            if s.sample == true {
                                                Text("Ejemplo").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.white.opacity(0.12)).cornerRadius(5)
                                            }
                                        }
                                        Text("\(fmtTime(s.ts)) · ⏱ \(fmtDur(s.dur)) · Cobertura \(s.coverage.map { "\($0)%" } ?? "—")")
                                            .foregroundColor(.secondary).font(.caption)
                                    }
                                    Spacer()
                                }
                                if let zc = zoneClasses(s) {
                                    DentureView(classes: zc)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .cornerRadius(14)
                                } else {
                                    Text("Sin datos de zonas").foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                } else if store.lastSync != nil && store.lastSess == 0 {
                    emptyCard("No había sesiones nuevas en el cepillo.\nEs normal: si la app oficial de Oclean se conectó antes, descargó el historial ella.\nCepíllate y sincroniza de nuevo aquí.")
                } else {
                    emptyCard("Aún no hay cepillados hoy.\nConecta el cepillo para descargar tu historial.")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 96) // hueco de la tab bar flotante
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
            VStack(spacing: 8) {
                Text("🦷").font(.title)
                Text(text).multilineTextAlignment(.center).foregroundColor(.secondary).font(.footnote)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct BatteryBar: View {
    let value: Int?
    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(value ?? 0) / 100)
                }
            }
            .frame(height: 10)
            Text(value.map { "\($0)%" } ?? "—").font(.subheadline.weight(.semibold))
        }
    }
    private var barColor: Color {
        guard let v = value else { return Color.white.opacity(0.2) }
        if v <= 20 { return Color(red: 1, green: 0.27, blue: 0.23) }
        if v <= 50 { return Color.orange }
        return Theme.accent
    }
}
