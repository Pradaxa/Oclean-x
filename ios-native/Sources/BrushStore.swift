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
    /* Modo a medida (0206 pnum 0): gear compuesto + duración total en segundos.
       Van siempre juntos: son un único paquete de esquema. */
    var customGear: Int?
    var customSeconds: Int?
    /* Cambio de zona: aviso cada 30s para cambiar de cuadrante (020D on/off) */
    var areaRemind: Bool?
    var isEmpty: Bool {
        customGear == nil && customSeconds == nil && areaRemind == nil
    }
}

/* Gear compuesto a partir de modo + potencia (1-32), igual que el menú del
   cepillo. HECHO (API oficial): gears 1-32 = limpieza, 33-36 = blanqueado 1-4,
   37-40 = masaje 1-4. SUPOSICIÓN: cómo se reparte la potencia 1-32 sobre los 4
   gears de blanqueado/masaje (por cuartiles); en limpieza va directa. */
func composedGear(mode: Int, power: Int) -> Int {
    let p = max(1, min(32, power))
    switch mode {
    case 1: return 33 + (p - 1) / 8  // blanquear -> 33-36
    case 2: return 37 + (p - 1) / 8  // masajear -> 37-40
    default: return p                // limpiar  -> 1-32
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

/* Modo a medida: un único gear repetido en tramos de 30s hasta la duración
   (2:00 / 2:30 / 3:00 -> 4 / 5 / 6 tramos). Se escribe como pnum 0, el modo
   "actual" del cepillo. SUPOSICIÓN verificable: pnum 0 es donde el cepillo
   guarda su modo del menú; tras sincronizar, el cepillo debería mostrar el
   modo elegido y el 0302 confirmar pnum 0. */
func buildCustomPackets(gear: Int, totalSeconds: Int) -> [[UInt8]] {
    let steps = max(1, min(8, totalSeconds / 30))
    var pl: [UInt8] = [0x02, 0x06, 0x00, UInt8(steps)]
    for _ in 0..<steps {
        pl.append(UInt8(GEAR_ENC[gear] ?? 0))
        pl.append(UInt8(gear & 0xff))
        pl.append(30)
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
    @Published var headDays: Int? = nil
    @Published var headTimes: Int? = nil
    @Published var brushMode: Int? = nil
    @Published var areaRemind: Bool = false
    @Published var model: String? = nil
    @Published var pending = PendingSettings()
    @Published var lastSess: Int = -1
    @Published var lastSync: Double? = nil

    /* Opciones de cepillado (las 4 del menú del cepillo, petición de Adrián):
       modo 0=limpiar/1=blanquear/2=masajear, potencia 1-32, duración en
       segundos. La app no puede leer del cepillo la potencia ni el modo actual
       (el 0302 solo confirma pnum), así que muestra lo elegido aquí. */
    @Published var ajMode: Int = 0
    @Published var ajPower: Int = 16
    @Published var ajDuration: Int = 120

    func setAjustes(mode: Int? = nil, power: Int? = nil, duration: Int? = nil) {
        if let mode { ajMode = mode }
        if let power { ajPower = max(1, min(32, power)) }
        if let duration { ajDuration = duration }
        pending.customGear = composedGear(mode: ajMode, power: ajPower)
        pending.customSeconds = ajDuration
        save()
    }

    func setAreaRemind(_ v: Bool) {
        pending.areaRemind = v
        save()
    }
    // Resultado de la verificación de ajustes contra el cepillo (transitorio, no se guarda)
    @Published var settingsCheck: String? = nil

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("store.json")
    }

    private struct Persisted: Codable {
        var sessions: [BrushSession]
        var battery: Int?; var headDays: Int?; var headTimes: Int?
        var brushMode: Int?; var areaRemind: Bool
        var model: String?; var pending: PendingSettings; var lastSync: Double?
        var ajMode: Int?; var ajPower: Int?; var ajDuration: Int?
    }

    init() {
        load()
        // Datos de demostración solo para capturas del simulador (-seedDemo); no se guardan.
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") {
            sessions = Self.samples()
            battery = 82; headDays = 90; headTimes = 12
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
        sessions = []; battery = nil; headTimes = nil; headDays = nil
        model = nil; lastSync = nil; lastSess = -1
        brushMode = nil; areaRemind = false
        pending = PendingSettings()
        ajMode = 0; ajPower = 16; ajDuration = 120
        save()
    }

    func save() {
        let p = Persisted(sessions: sessions, battery: battery, headDays: headDays, headTimes: headTimes,
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
