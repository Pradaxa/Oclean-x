import Foundation
import Combine

/* ---------- Modelos (port de app.js v14) ---------- */

struct BrushSession: Codable, Identifiable {
    var ts: Double          // ms epoch, como en la web
    var pnum: Int?
    var dur: Int?
    var durSched: Int?
    var score: Int?
    var zones: [Int]?
    var coverage: Int?
    var sample: Bool?
    var id: Double { ts }
}

struct PendingSettings: Codable {
    /* Modo y potencia (0206 sobre programa de fábrica): gear compuesto +
       duración total en segundos. Van siempre juntos: un único paquete. */
    var customGear: Int?
    var customSeconds: Int?
    /* Cambio de zona: aviso cada 30s para cambiar de cuadrante (020D on/off) */
    var areaRemind: Bool?
    var isEmpty: Bool {
        customGear == nil && customSeconds == nil && areaRemind == nil
    }
}

/* Gear compuesto a partir de modo + potencia. HECHO (API oficial + confirmado
   por Adrián en su cepillo 13:08): limpiar tiene potencia 1-32 (gear =
   potencia), blanquear y masajear tienen potencia 1-4 (gears 33-36 y 37-40). */
func maxPower(for mode: Int) -> Int { mode == 0 ? 32 : 4 }

func composedGear(mode: Int, power: Int) -> Int {
    switch mode {
    case 1: return 32 + max(1, min(4, power))  // blanquear -> 33-36
    case 2: return 36 + max(1, min(4, power))  // masajear  -> 37-40
    default: return max(1, min(32, power))     // limpiar   -> 1-32
    }
}

/* Esquemas OCLEANY3: pnum -> (nombre, [[gear,seg]]) (tabla de paquetes de app.js) */
let GEAR_ENC: [Int: Int] = [1:5,2:6,3:7,4:8,5:17,6:18,7:19,8:20,9:21,10:22,11:23,12:24]
let SCHEMES: [Int: (String, [[Int]])] = [
    0:("Limpieza estándar",[[2,30],[2,30],[2,30],[2,30]]),
    72:("Limpieza media-fuerte",[[16,30],[16,30],[24,30],[16,30],[16,30],[37,30]]),
    73:("Limpieza fuerte",[[38,30],[24,30],[24,30],[24,30],[24,30],[32,30]]),
    74:("Sensible post-lavado",[[8,30],[8,30],[37,30],[8,30],[8,30]]),
    75:("Blanqueo diario",[[34,30],[34,30],[24,30],[16,30],[16,30]]),
    76:("Blanqueo medio",[[32,30],[35,30],[24,30],[24,30],[35,30]]),
    77:("Súper blanqueo",[[32,30],[36,30],[32,30],[36,30],[32,30]]),
    78:("Limpieza sensible",[[37,30],[41,30],[41,30],[41,30],[41,30],[41,30]]),
    79:("SPA suave",[[8,30],[33,30],[33,30],[37,30],[37,30],[8,30]]),
    80:("SPA estándar",[[38,30],[38,30],[34,30],[34,30],[16,30],[16,30]]),
    81:("SPA profundo",[[39,30],[35,30],[24,30],[24,30],[39,30],[35,30]]),
    82:("Tras dulces",[[18,30],[18,30],[12,30],[12,30]]),
    83:("Frescor post-comida",[[41,30],[41,30],[1,30],[41,30],[41,30]]),
    84:("Masaje de encías",[[38,30],[38,30],[38,30],[38,30]]),
    85:("Cuidado de encías",[[8,30],[8,30],[37,30],[8,30],[8,30],[37,20],[8,30]]),
    86:("Blanqueo principiante",[[33,30],[6,30],[33,30],[6,30],[6,30]]),
    87:("Limpieza con brackets",[[8,30],[8,30],[8,30],[8,30],[8,30],[8,30]]),
    88:("Limpieza rápida",[[30,20],[30,20],[30,20],[30,20]]),
    89:("Viaje",[[17,30],[17,30],[35,30],[35,30]]),
    90:("Cuidado gestación",[[12,30],[12,30],[20,30],[38,30],[12,30],[12,30]])
]

func schemeName(_ pnum: Int?) -> String {
    if let p = pnum, let s = SCHEMES[p] { return s.0 }
    return pnum == nil ? "Cepillado" : "Programa \(pnum!)"
}

/* HECHO (probado con nRF en el OCLEANY3 de Adrián, 12-nov 17:43): escribir un
   programa de FÁBRICA con 0206 lo activa y el cepillo adopta gears y duración
   (pnum 84 gear 40 -> pantalla "Masajear 4"). Escribir pnum 0 es un no-op en
   su firmware (ACK OK pero no cambia nada; el "18" era basura de pantalla).
   Vehículos: Limpiar -> pnum 72, Blanquear -> pnum 75, Masajear -> pnum 84.
   Efecto secundario conocido: la definición de esos programas en el cepillo
   queda sobrescrita con nuestros tramos. */
func programPnum(forGear gear: Int) -> Int { gear >= 37 ? 84 : (gear >= 33 ? 75 : 72) }
func mode(forGear gear: Int) -> Int { gear >= 37 ? 2 : (gear >= 33 ? 1 : 0) }

func buildCustomPackets(gear: Int, totalSeconds: Int) -> [[UInt8]] {
    /* Máximo 4 tramos: con 4 el paquete mide 18 bytes y cabe en UNA escritura
       BLE (MTU 23). Con 5-6 tramos (2:30/3:00 a 30s) salía partido en dos
       escrituras (0206 + continuación 020B) y en el OCLEANY3 de Adrián la sync
       partida dejó la pantalla con valores absurdos (duración 6'13"). Tramos
       de duración variable están respaldados por los esquemas oficiales del
       APK (pnum 85 lleva un tramo de 20s; pnum 88 son todos de 20s). */
    let steps = totalSeconds <= 120 ? max(1, totalSeconds / 30) : 4
    let base = totalSeconds / steps, extra = totalSeconds % steps
    var pl: [UInt8] = [0x02, 0x06, UInt8(programPnum(forGear: gear) & 0xff), UInt8(steps)]
    for i in 0..<steps {
        pl.append(UInt8(GEAR_ENC[gear] ?? 0))
        pl.append(UInt8(gear & 0xff))
        pl.append(UInt8(base + (i < extra ? 1 : 0)))
    }
    pl.append(0x00); pl.append(0x05)
    if pl.count > 20 {
        return [Array(pl.prefix(16)) + [0x2a, 0x2b], [0x02, 0x0b] + Array(pl.dropFirst(16))]
    }
    return [pl]
}

let ZONES_FULL = ["Superior izq. exterior","Superior izq. interior","Inferior izq. exterior","Inferior izq. interior",
                  "Superior der. exterior","Superior der. interior","Inferior der. exterior","Inferior der. interior"]

enum ZoneClass: String {
    case good, mid, bad, none
}

/* Port de zoneClasses(s) */
func zoneClasses(_ s: BrushSession) -> [ZoneClass]? {
    guard let zones = s.zones else { return nil }
    let sum = zones.reduce(0, +)
    let dur = Double(s.dur ?? s.durSched ?? 120)
    return zones.map { v -> ZoneClass in
        if v == 0 || sum <= 0 { return .bad }
        let norm = Double(v) / Double(sum) * dur
        return norm >= 9 ? .good : (norm >= 4 ? .mid : .bad)
    }
}

/* Registro de 42 bytes (port de parseSessionRecord) */
func parseSessionRecord(_ r: [UInt8]) -> BrushSession? {
    if r.count < 42 { return nil }
    let year = Int(r[0]) + 2000
    if year < 2020 { return nil }
    var comps = DateComponents()
    comps.year = year; comps.month = Int(r[1]); comps.day = Int(r[2])
    comps.hour = Int(r[3]); comps.minute = Int(r[4]); comps.second = Int(r[5])
    guard let date = Calendar.current.date(from: comps) else { return nil }
    let ts = date.timeIntervalSince1970 * 1000
    let sched = (Int(r[7]) << 8) | Int(r[8])
    let valid = (Int(r[9]) << 8) | Int(r[10])
    var dur: Int? = nil
    if valid > 0 && (sched == 0 || valid <= sched) { dur = valid } else if sched > 0 { dur = sched }
    var score: Int? = Int(r[33]); if !(score! > 0 && score! <= 100) { score = nil }
    let zones = [Int(r[23]),Int(r[24]),Int(r[25]),Int(r[26]),Int(r[27]),Int(r[28]),Int(r[29]),Int(r[30])]
    let total = zones.reduce(0, +)
    var coverage: Int? = nil
    if total > 0 && sched > 0 {
        let thr = 9.0 / Double(sched)
        let covered = zones.filter { Double($0) / Double(total) >= thr }.count
        coverage = Int((Double(covered) / 8.0 * 100.0).rounded())
    }
    return BrushSession(ts: ts, pnum: Int(r[6]), dur: dur, durSched: sched > 0 ? sched : nil,
                        score: score, zones: zones.contains(where: { $0 > 0 }) ? zones : nil, coverage: coverage, sample: nil)
}

final class BrushStore: ObservableObject {
    @Published var sessions: [BrushSession] = []
    @Published var battery: Int? = nil
    @Published var headDays: Int? = nil      // contador del cepillo (0302); ya no se usa para el recordatorio
    @Published var headTimes: Int? = nil
    @Published var headChangedAt: Double? = nil  // recordatorio LOCAL de cabezal (90 días)
    @Published var brushMode: Int? = nil
    @Published var areaRemind: Bool = false
    @Published var model: String? = nil
    @Published var pending = PendingSettings()
    @Published var lastSess: Int = -1
    @Published var lastSync: Double? = nil

    /* Opciones de cepillado (las 4 del menú del cepillo, petición de Adrián):
       modo 0=limpiar/1=blanquear/2=masajear, potencia 1-32 en limpiar y 1-4 en
       blanquear/masajear (confirmado en su cepillo), duración en segundos. La
       app no puede leer del cepillo la potencia ni el modo actual (el 0302
       solo confirma pnum), así que muestra lo elegido aquí. */
    @Published var ajMode: Int = 0
    @Published var ajPower: Int = 16
    @Published var ajDuration: Int = 120

    func setAjustes(mode: Int? = nil, power: Int? = nil, duration: Int? = nil) {
        if let mode, mode != ajMode {
            /* La escala de potencia cambia con el modo: al saltar entre 1-32 y
               1-4 se remapea en proporción para no perder la intensidad. */
            let oldMax = maxPower(for: ajMode), newMax = maxPower(for: mode)
            if oldMax == 32 && newMax == 4 { ajPower = (ajPower - 1) / 8 + 1 }
            else if oldMax == 4 && newMax == 32 { ajPower = ajPower * 8 }
            ajMode = mode
        }
        if let power { ajPower = power }
        ajPower = max(1, min(maxPower(for: ajMode), ajPower))
        if let duration { ajDuration = duration }
        pending.customGear = composedGear(mode: ajMode, power: ajPower)
        pending.customSeconds = ajDuration
        save()
    }

    func setAreaRemind(_ v: Bool) {
        pending.areaRemind = v
        save()
    }

    /* Pedido de Adrián (voz 02:56, 13-nov): el cabezal es un recordatorio
       LOCAL, independiente del cepillo: cuenta atrás de 90 días en la app,
       sin 020F ni lectura del contador del cepillo. "Cambiar" reinicia a 90
       al instante. headChangedAt = momento (ms epoch) del último cambio. */
    func changeHeadNow() {
        headChangedAt = Date().timeIntervalSince1970 * 1000
        save()
    }

    /* Días que quedan (90 -> 0); nil si nunca se ha marcado un cambio. */
    var headRemaining: Int? {
        guard let t = headChangedAt else { return nil }
        let elapsed = Int((Date().timeIntervalSince1970 * 1000 - t) / 86_400_000)
        return max(0, 90 - elapsed)
    }
    // Resultado de la verificación de ajustes contra el cepillo (transitorio, no se guarda)
    @Published var settingsCheck: String? = nil

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("store.json")
    }

    private struct Persisted: Codable {
        var sessions: [BrushSession]
        var battery: Int?; var headDays: Int?; var headTimes: Int?; var headChangedAt: Double?
        var brushMode: Int?; var areaRemind: Bool
        var model: String?; var pending: PendingSettings; var lastSync: Double?
        var ajMode: Int?; var ajPower: Int?; var ajDuration: Int?
    }

    init() {
        load()
        /* Pedido de Adrián (15:18): los cepillados de menos de 10 s no cuentan.
           Purgamos los ya guardados una vez al cargar. */
        let before = sessions.count
        sessions.removeAll { ($0.dur ?? 10) < 10 }
        if sessions.count != before { save() }
        // Datos de demostración solo para capturas del simulador (-seedDemo); no se guardan.
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") {
            sessions = Self.samples()
            battery = 82; headDays = 23; headTimes = 41
            headChangedAt = Date().timeIntervalSince1970 * 1000 - 23 * 86_400_000
            brushMode = 0; model = "OCLEANY3"
            areaRemind = true
            lastSync = Date().timeIntervalSince1970 * 1000; lastSess = 0
        }
    }

    static func samples() -> [BrushSession] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Double {
            var c = cal.dateComponents([.year,.month,.day], from: Date())
            c.hour = h; c.minute = m
            return (cal.date(from: c) ?? Date()).timeIntervalSince1970 * 1000
        }
        return [
            BrushSession(ts: at(7,42),  pnum: 0,  dur: 120, durSched: 120, score: 92, zones: [120,110,90,80,115,100,70,60], coverage: 88, sample: true),
            BrushSession(ts: at(14,15), pnum: 88, dur: 80,  durSched: 80,  score: 71, zones: [80,40,20,0,90,60,30,10],      coverage: 63, sample: true),
            BrushSession(ts: at(22,5),  pnum: 0,  dur: 118, durSched: 120, score: 84, zones: [110,90,70,50,100,95,55,40],  coverage: 75, sample: true)
        ]
    }

    @discardableResult
    func mergeSession(_ s: BrushSession) -> Bool {
        // Menos de 10 s no es un cepillado (pedido de Adrián 15:18): no se guarda.
        if let d = s.dur, d < 10 { return false }
        if let i = sessions.firstIndex(where: { $0.ts == s.ts }) {
            var ex = sessions[i]; var changed = false
            if ex.pnum == nil, s.pnum != nil { ex.pnum = s.pnum; changed = true }
            if ex.dur == nil, s.dur != nil { ex.dur = s.dur; changed = true }
            if ex.durSched == nil, s.durSched != nil { ex.durSched = s.durSched; changed = true }
            if s.score != nil { ex.score = s.score; changed = true }
            if ex.zones == nil, s.zones != nil { ex.zones = s.zones; changed = true }
            if ex.coverage == nil, s.coverage != nil { ex.coverage = s.coverage; changed = true }
            sessions[i] = ex
            return changed
        }
        sessions.append(s)
        return true
    }

    func sortSessions() { sessions.sort { $0.ts > $1.ts } }
    func newestSession() -> BrushSession? { sessions.first }

    func sessionsOn(_ day: Date) -> [BrushSession] {
        let cal = Calendar.current
        return sessions.filter { cal.isDate(Date(timeIntervalSince1970: $0.ts/1000), inSameDayAs: day) }
    }

    /* ---------- Datos: exportar / restaurar / borrar (port de doExport/doImport/doWipe) ---------- */

    func exportData() -> Data? {
        try? JSONEncoder().encode(sessions)
    }

    @discardableResult
    func importData(_ data: Data) -> Int {
        guard let arr = try? JSONDecoder().decode([BrushSession].self, from: data) else { return -1 }
        var n = 0
        for s in arr where mergeSession(s) { n += 1 }
        sortSessions(); save()
        return n
    }

    func wipe() {
        sessions = []; battery = nil; headTimes = nil; headDays = nil; headChangedAt = nil
        model = nil; lastSync = nil; lastSess = -1
        brushMode = nil; areaRemind = false
        pending = PendingSettings()
        ajMode = 0; ajPower = 16; ajDuration = 120
        save()
    }

    func save() {
        let p = Persisted(sessions: sessions, battery: battery, headDays: headDays, headTimes: headTimes, headChangedAt: headChangedAt,
                          brushMode: brushMode, areaRemind: areaRemind,
                          model: model, pending: pending, lastSync: lastSync,
                          ajMode: ajMode, ajPower: ajPower, ajDuration: ajDuration)
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: fileURL, options: .atomic) }
    }

    private func load() {
        guard let d = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: d) else { return }
        sessions = p.sessions; battery = p.battery; headDays = p.headDays; headTimes = p.headTimes
        brushMode = p.brushMode; areaRemind = p.areaRemind
        model = p.model; pending = p.pending; lastSync = p.lastSync
        ajMode = p.ajMode ?? 0; ajPower = p.ajPower ?? 16; ajDuration = p.ajDuration ?? 120
        headChangedAt = p.headChangedAt
        /* Migración al recordatorio local (13-nov): si nunca marcó un cambio
           pero el cepillo decía cuántos días llevaba el cabezal, la cuenta
           atrás arranca desde ahí para que no pierda lo que ya llevaba. */
        if headChangedAt == nil, let hd = headDays {
            headChangedAt = Date().timeIntervalSince1970 * 1000 - Double(hd) * 86_400_000
            save()
        }
    }
}

/* ---------- Formato ---------- */
func fmtTime(_ ts: Double) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ts/1000))
}
func fmtDay(_ ts: Double) -> String {
    let d = Date(timeIntervalSince1970: ts/1000)
    let cal = Calendar.current
    let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "d MMM"
    if cal.isDateInToday(d) { return "Hoy" }
    if cal.isDateInYesterday(d) { return "Ayer" }
    return f.string(from: d)
}
func fmtDur(_ dur: Int?) -> String {
    guard let d = dur else { return "—" }
    return String(format: "%d:%02d", d/60, d%60)
}
