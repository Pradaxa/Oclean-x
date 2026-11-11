import SwiftUI

struct HistorialView: View {
    @EnvironmentObject var store: BrushStore
    @State private var detail: BrushSession? = nil

    private var byDay: [(String, [BrushSession])] {
        var groups: [(String, [BrushSession])] = []
        for s in store.sessions {
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
                    if store.sessions.isEmpty {
                        Text("Aún no hay cepillados. Sincroniza tu cepillo desde la pestaña Hoy.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(byDay, id: \.0) { day, list in
                        Text(day).foregroundColor(.secondary).font(.footnote)
                        Card {
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
                                    }
                                    .buttonStyle(.plain)
                                    if i < list.count - 1 { Divider().background(Color.white.opacity(0.08)) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .sheet(item: $detail) { s in
            SessionDetailSheet(session: s)
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
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                        }
                    }
                    Text(schemeName(session.pnum)).font(.title2.bold())
                    Text("\(fmtDay(session.ts)) · \(fmtTime(session.ts))").foregroundColor(.secondary)
                    ScoreRing(score: session.score, size: 86)
                    Text("⏱ \(fmtDur(session.dur)) · Cobertura \(session.coverage.map { "\($0)%" } ?? "—")")
                        .foregroundColor(.secondary)
                    if let zc = zoneClasses(session) {
                        DentureView(classes: zc).frame(height: 400)
                    } else {
                        Text("Sin datos de zonas").foregroundColor(.secondary).padding(.vertical, 40)
                    }
                    if let z = session.zones {
                        Card {
                            VStack(spacing: 8) {
                                ForEach(0..<8, id: \.self) { i in
                                    HStack {
                                        Text(ZONES_FULL[i]).font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(z[i])").font(.caption)
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
}
