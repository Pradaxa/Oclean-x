import SwiftUI

struct HistorialView: View {
    @EnvironmentObject var store: BrushStore
    @State private var detail: BrushSession? = nil

    private var shown: [BrushSession] {
        store.sessions.isEmpty ? BrushStore.samples() : store.sessions
    }
    private var isSample: Bool { store.sessions.isEmpty }

    private var byDay: [(String, [BrushSession])] {
        var groups: [(String, [BrushSession])] = []
        for s in shown {
            let label = fmtDay(s.ts)
            if let i = groups.firstIndex(where: { $0.0 == label }) { groups[i].1.append(s) }
            else { groups.append((label, [s])) }
        }
        return groups
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Historial").font(.largeTitle.bold()).padding(.top, 8)
                    if isSample {
                        Text("HISTORIAL · EJEMPLO").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }
                    ForEach(byDay, id: \.0) { day, list in
                        let scores = list.compactMap { $0.score }
                        let avg = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(day).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(list.count) \(list.count == 1 ? "cepillado" : "cepillados")" + (avg.map { " · media \($0)" } ?? ""))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            GlassCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                                        Button(action: { detail = s }) {
                                            HStack(spacing: 14) {
                                                ScoreRing(score: s.score, size: 44)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(schemeName(s.pnum)).font(.subheadline.weight(.semibold))
                                                    Text("\(fmtTime(s.ts)) · ⏱ \(fmtDur(s.dur)) · Cobertura \(s.coverage.map { "\($0)%" } ?? "—")")
                                                        .foregroundColor(.secondary).font(.caption)
                                                }
                                                Spacer()
                                                if s.sample == true {
                                                    Text("Ejemplo").font(.caption2).foregroundColor(.secondary)
                                                }
                                                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                                            }
                                            .padding(.vertical, 10)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("session-row")
                                        if i < list.count - 1 { Divider().background(Color.white.opacity(0.08)) }
                                    }
                                }
                            }
                        }
                    }
                    if isSample {
                        Text("Cuando sincronices el cepillo verás aquí tus días reales.")
                            .font(.footnote).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .sheet(item: $detail) { s in
            SessionDetailSheet(session: s)
        }
        .onAppear {
            let a = ProcessInfo.processInfo.arguments
            if a.contains("-openDetailBad"), detail == nil,
               let bad = shown.first(where: { (zoneClasses($0) ?? []).contains(.bad) }) {
                detail = bad
            } else if a.contains("-openDetail"), detail == nil, let first = shown.first {
                detail = first
            }
        }
    }
}

struct SessionDetailSheet: View {
    let session: BrushSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill").font(.title2)
                                .foregroundColor(.secondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityIdentifier("detail-close")
                    }
                    Text(schemeName(session.pnum)).font(.title2.bold())
                    Text("\(fmtDay(session.ts)) · \(fmtTime(session.ts))").foregroundColor(.secondary)
                    ScoreRing(score: session.score, size: 86)
                    Text("⏱ \(fmtDur(session.dur)) · Cobertura \(session.coverage.map { "\($0)%" } ?? "—")")
                        .foregroundColor(.secondary)
                    if let zc = zoneClasses(session) {
                        GlassCard {
                            DentureView(classes: zc).frame(height: 340)
                        }
                    } else {
                        Text("Sin datos de zonas").foregroundColor(.secondary).padding(.vertical, 40)
                    }
                    if let z = session.zones {
                        let zc = zoneClasses(session) ?? Array(repeating: .none, count: 8)
                        GlassCard {
                            VStack(spacing: 10) {
                                ForEach(0..<8, id: \.self) { i in
                                    HStack(spacing: 10) {
                                        Circle().fill(dotColor(zc[i])).frame(width: 8, height: 8)
                                        Text(ZONES_FULL[i]).font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(z[i])").font(.caption.monospacedDigit())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func dotColor(_ c: ZoneClass) -> Color {
        switch c {
        case .good: return Color(red: 0.55, green: 0.85, blue: 0.62)
        case .mid: return Color(red: 0.94, green: 0.65, blue: 0.35)
        case .bad: return Theme.accent
        case .none: return Color.white.opacity(0.2)
        }
    }
}
