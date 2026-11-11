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

                    // Tarjeta del cepillo
                    Card {
                        HStack(spacing: 18) {
                            if let url = Bundle.main.url(forResource: "brush", withExtension: "png", subdirectory: "web/assets"),
                               let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img).resizable().scaledToFit()
                                    .frame(width: 74, height: 150)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Batería").foregroundColor(.secondary)
                                ProgressView(value: Double(store.battery ?? 0), total: 100)
                                    .tint(Theme.accent)
                                Text(store.battery.map { "\($0)%" } ?? "—").font(.headline)
                                Text("Cabezal").foregroundColor(.secondary).padding(.top, 4)
                                Text(store.headDays.map { "\($0) días" } ?? "—").font(.headline)
                            }
                            Spacer()
                        }
                    }

                    // Sincronizar
                    Button(action: { ble.sync() }) {
                        HStack {
                            if ble.statusBusy { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.triangle.2.circlepath") }
                            Text(ble.statusBusy ? "Sincronizando…" : "Sincronizar").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .cornerRadius(16)
                    .disabled(ble.connecting)

                    HStack(spacing: 6) {
                        Circle().fill(ble.statusBusy ? Color.orange : (store.battery != nil ? Color.green : Color.gray))
                            .frame(width: 8, height: 8)
                        Text(ble.status).foregroundColor(.secondary).font(.footnote)
                    }

                    // Cepillados de hoy
                    if !todaySessions.isEmpty {
                        Text(todaySessions.allSatisfy { $0.sample == true } ? "Cepillados de hoy · ejemplo" : "Cepillados de hoy")
                            .foregroundColor(.secondary).font(.footnote)
                        HStack(spacing: 10) {
                            ForEach(todaySessions) { s in
                                Button(action: { selected = s }) {
                                    VStack(spacing: 2) {
                                        Text(fmtTime(s.ts)).fontWeight(.semibold)
                                        Text(s.score.map { "\($0)" } ?? "—").font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background((shown?.ts == s.ts) ? Theme.accent.opacity(0.45) : Color.white.opacity(0.07))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .background(Theme.cardBg)
                        .cornerRadius(16)
                    }

                    // Sesión seleccionada
                    if let s = shown {
                        Card {
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
                                        .frame(height: 400)
                                        .cornerRadius(12)
                                } else {
                                    Text("Sin datos de zonas").foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
    }
}
