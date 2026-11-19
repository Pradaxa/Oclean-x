import SwiftUI

/* Tendencias (pedido de Adrián 02:03, 13-nov): evolución del cepillado en los
   últimos 14 días. iOS 15 no tiene Swift Charts: barras hechas a mano. */
struct TendenciasView: View {
    @EnvironmentObject var store: BrushStore
    @StateObject private var scrollLock = ScrollLock()

    private struct DayStats {
        let initial: String   // inicial del día de la semana ("L", "M", ...)
        let count: Int
        let avgDur: Int?      // segundos
        let avgScore: Int?
    }

    /* Serie de demostración cuando no hay datos reales (o solo ejemplos):
       misma idea que Historial ("EJEMPLO"), para capturas y primer arranque. */
    private var isSample: Bool {
        store.sessions.isEmpty || store.sessions.allSatisfy { $0.sample == true }
    }

    private var days: [DayStats] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).map { i in
            let d = cal.date(byAdding: .day, value: i - 13, to: today) ?? today
            if isSample {
                let c  = [1, 2, 2, 0, 2, 1, 2, 2, 0, 1, 2, 2, 1, 3][i]
                let du = [95, 110, 124, 0, 130, 88, 120, 115, 0, 102, 126, 118, 90, 135][i]
                let sc = [68, 75, 82, 0, 88, 70, 79, 84, 0, 72, 90, 86, 74, 91][i]
                return DayStats(initial: initial(d), count: c,
                                avgDur: du > 0 ? du : nil, avgScore: sc > 0 ? sc : nil)
            }
            let ss = store.sessionsOn(d)
            let durs = ss.compactMap { $0.dur }
            let scores = ss.compactMap { $0.score }
            return DayStats(initial: initial(d), count: ss.count,
                            avgDur: durs.isEmpty ? nil : durs.reduce(0, +) / durs.count,
                            avgScore: scores.isEmpty ? nil : scores.reduce(0, +) / scores.count)
        }
    }

    private struct ZoneStat {
        let avg: Double      // segundos normalizados medios por cepillado
        let cls: ZoneClass
    }

    /* Zonas (pedido de Adrián 17:20, 19-nov): con TODOS los cepillados
       guardados, qué partes se cepilla mejor y cuáles peor. Por zona, la
       media de los segundos que le dedica en cada cepillado (misma
       normalización que zoneClasses) con los mismos umbrales: >= 9 s bien,
       >= 4 s regular, menos mal. */
    private var zoneAgg: (stats: [ZoneStat], count: Int)? {
        let src = isSample ? BrushStore.samples() : store.sessions
        var totals = [Double](repeating: 0, count: 8)
        var n = 0
        for s in src {
            guard let secs = zoneSeconds(s) else { continue }
            for i in 0..<8 { totals[i] += secs[i] }
            n += 1
        }
        guard n > 0 else { return nil }
        return ((0..<8).map { i -> ZoneStat in
            let avg = totals[i] / Double(n)
            return ZoneStat(avg: avg, cls: avg >= 9 ? .good : (avg >= 4 ? .mid : .bad))
        }, n)
    }

    private func initial(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        let wd = Calendar.current.component(.weekday, from: d)
        return String(f.shortWeekdaySymbols[wd - 1].prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tendencias").font(.largeTitle.bold()).padding(.top, 8)
                    if isSample {
                        Text("TENDENCIAS · EJEMPLO").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }

                    // Cepillados al día
                    let maxCount = max(3, days.map(\.count).max() ?? 0)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cepillados al día").font(.headline)
                            barChart(days.map { Double($0.count) }, maxValue: Double(maxCount), target: 2)
                            dayLabels
                            let avg = Double(days.map(\.count).reduce(0, +)) / 14.0
                            Text(String(format: "Media: %.1f al día · la línea marca 2", avg))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("tendencias-count")

                    // Duración media
                    let maxDur = max(150, days.compactMap(\.avgDur).max() ?? 0)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duración media").font(.headline)
                            barChart(days.map { $0.avgDur.map(Double.init) }, maxValue: Double(maxDur), target: 120)
                            dayLabels
                            let ds = days.compactMap(\.avgDur)
                            Text("Media: \(ds.isEmpty ? "—" : fmtDur(ds.reduce(0, +) / ds.count)) · la línea marca 2:00")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("tendencias-dur")

                    // Puntuación media
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Puntuación media").font(.headline)
                            barChart(days.map { $0.avgScore.map(Double.init) }, maxValue: 100)
                            dayLabels
                            let sc = days.compactMap(\.avgScore)
                            Text(sc.isEmpty ? "Sin puntuaciones todavía" : "Media: \(sc.reduce(0, +) / sc.count) sobre 100")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("tendencias-score")

                    // Zonas: qué partes se cepilla mejor y cuáles peor
                    if let agg = zoneAgg {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Qué zonas cepillas mejor").font(.headline)
                                Text("Media de todos tus cepillados (\(agg.count))")
                                    .font(.caption).foregroundColor(.secondary)
                                DentureView(classes: agg.stats.map(\.cls), scrollLock: scrollLock)
                                    .frame(height: 280)
                                let maxV = max(1, agg.stats.map(\.avg).max() ?? 1)
                                VStack(spacing: 8) {
                                    ForEach(0..<8, id: \.self) { i in
                                        HStack(spacing: 8) {
                                            Circle().fill(zoneColor(agg.stats[i].cls)).frame(width: 8, height: 8)
                                            Text(ZONES_FULL[i]).font(.caption).foregroundColor(.secondary)
                                                .frame(width: 132, alignment: .leading)
                                            GeometryReader { g in
                                                ZStack(alignment: .leading) {
                                                    Capsule().fill(Color.white.opacity(0.08))
                                                    Capsule().fill(zoneColor(agg.stats[i].cls).opacity(0.85))
                                                        .frame(width: max(4, g.size.width * CGFloat(agg.stats[i].avg / maxV)))
                                                }
                                            }
                                            .frame(height: 8)
                                            Text("\(Int(agg.stats[i].avg.rounded())) s")
                                                .font(.caption.monospacedDigit())
                                                .frame(width: 36, alignment: .trailing)
                                        }
                                    }
                                }
                                let best = agg.stats.enumerated().max(by: { $0.element.avg < $1.element.avg })!.offset
                                let worst = agg.stats.enumerated().min(by: { $0.element.avg < $1.element.avg })!.offset
                                Text("Mejor: \(ZONES_FULL[best]) · Peor: \(ZONES_FULL[worst])")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .accessibilityIdentifier("tendencias-zonas")
                        .id("tendencias-zonas-anchor")
                    }

                    if isSample {
                        Text("Cuando sincronices el cepillo verás aquí tus tendencias reales.")
                            .font(.footnote).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollDisablediOS15(scrollLock.locked)
            .onAppear {
                // Solo capturas del simulador: bajar hasta la tarjeta de zonas.
                if ProcessInfo.processInfo.arguments.contains("-tendenciasZones") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation { proxy.scrollTo("tendencias-zonas-anchor", anchor: .top) }
                    }
                }
            }
            }
        }
    }

    private var dayLabels: some View {
        HStack(spacing: 4) {
            ForEach(0..<days.count, id: \.self) { i in
                Text(days[i].initial)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func barChart(_ values: [Double?], maxValue: Double, target: Double? = nil) -> some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<values.count, id: \.self) { i in
                        let v = values[i] ?? 0
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(v > 0 ? Theme.accent : Color.white.opacity(0.12))
                            .frame(height: max(3, CGFloat(v / maxValue) * h))
                    }
                }
                if let t = target, t > 0, t < maxValue {
                    let y = h - CGFloat(t / maxValue) * h
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: g.size.width, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(height: 110)
    }
}
