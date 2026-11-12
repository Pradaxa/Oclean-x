import Foundation
import CoreBluetooth
import Combine

/* Port directo del protocolo de app.js v14 (TYPE1 OCLEANY3):
   SVC 8082caa8, fbb85 escritura general, fbb86 estado, fbb89 comandos de sesión,
   fbb90 registros *B# de 42 bytes; batería 0x180f/0x2a19; DIS 0x180a/0x2a24. */
final class BLEManager: NSObject, ObservableObject {
    private let SVC  = CBUUID(string: "8082caa8-41a6-4021-91c6-56f9b954cc18")
    private let C_WRITE = CBUUID(string: "9d84b9a3-000c-49d8-9183-855b673fbb85")
    private let C_NOTIFY = CBUUID(string: "5f78df94-798c-46f5-990a-855b673fbb86")
    private let C_SEND = CBUUID(string: "5f78df94-798c-46f5-990a-855b673fbb89")
    private let C_RECV = CBUUID(string: "5f78df94-798c-46f5-990a-855b673fbb90")
    private let BATT_SVC = CBUUID(string: "180F")
    private let BATT_CHAR = CBUUID(string: "2A19")
    private let DIS_SVC = CBUUID(string: "180A")
    private let DIS_MODEL = CBUUID(string: "2A24")

    private let TZ_MIN = [-720,-660,-600,-540,-480,-420,-360,-300,-240,-210,-180,-120,-60,0,60,120,180,210,240,270,300,330,345,360,390,420,480,540,570,600,660,720,780]

    enum SyncError: Error { case bluetoothOff, notFound, cancelled, connectFailed }

    @Published var connecting = false
    @Published var status = "Cepillo sin conectar"
    @Published var statusBusy = false
    @Published var offerScanAll = false
    @Published var logLines: [String] = []

    struct BleCandidate: Identifiable { let id: UUID; let name: String }
    @Published var candidates: [BleCandidate] = []
    private var candidatesStore: [UUID: CBPeripheral] = [:]

    private let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ble-log.txt")

    var fullLogText: String { logLines.joined(separator: "\n") }

    /* Registro de diagnóstico persistente (equivalente al panel Diagnóstico de la web) */
    func dlog(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(msg)"
        Task { @MainActor in
            self.logLines.append(line)
            if self.logLines.count > 600 { self.logLines.removeFirst(self.logLines.count - 600) }
        }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    private func loadLog() {
        guard let d = try? Data(contentsOf: logURL), let s = String(data: d, encoding: .utf8) else { return }
        let lines = s.split(separator: "\n").map(String.init)
        Task { @MainActor in self.logLines = Array(lines.suffix(600)) }
    }

    func clearLog() {
        Task { @MainActor in self.logLines = [] }
        try? FileManager.default.removeItem(at: logURL)
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private weak var store: BrushStore?

    // Continuaciones puente delegate -> async
    private var scanCont: CheckedContinuation<CBPeripheral, Error>?
    private var connectCont: CheckedContinuation<Void, Error>?
    private var servicesCont: CheckedContinuation<Void, Error>?
    private var charsCont: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var writeCont: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var readCont: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private var notifyCont: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var descCont: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var centralReady: CheckedContinuation<Void, Never>?

    // Estado de la recogida de sesiones
    private var t1Active = false, t1Buf: [UInt8] = [], t1Expected = 0
    private var sessFetched = 0
    private var lastHex: [String: String] = [:]
    private var sessSignal: CheckedContinuation<Void, Never>?
    private var chars: [CBUUID: CBCharacteristic] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func attach(store: BrushStore) {
        self.store = store
        loadLog()
        if let ls = store.lastSync {
            var base = "Última sincronización: \(fmtDay(ls)) · \(fmtTime(ls))"
            if store.lastSess == 0 { base += " · sin sesiones nuevas en el cepillo" }
            else if store.lastSess > 0 { base += " · \(store.lastSess) \(store.lastSess == 1 ? "nueva" : "nuevas")" }
            status = base
        }
    }

    @MainActor private func setStatus(_ s: String, busy: Bool) {
        status = s; statusBusy = busy
    }

    private func ready() async {
        if central.state != .unknown { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            centralReady = c
        }
    }

    func sync(auto: Bool = false) {
        guard !connecting else { return }
        connecting = true
        Task { @MainActor in self.offerScanAll = false }
        dlog("--- sync inicio\(auto ? " (automático al abrir)" : "") ---")
        runWithStatus(known: nil, auto: auto, attempt: 1)
    }

    func connectCandidate(_ c: BleCandidate) {
        guard !connecting, let p = candidatesStore[c.id] else { return }
        connecting = true
        Task { @MainActor in self.offerScanAll = false }
        dlog("conectando con candidato: \(c.name)")
        runWithStatus(known: p, auto: false, attempt: 1)
    }

    private func runWithStatus(known: CBPeripheral?, auto: Bool, attempt: Int) {
        Task {
            await setStatus("Buscando el cepillo…", busy: true)
            do {
                try await runSync(known: known)
                let n = store?.lastSess ?? -1
                if n == 0 { await setStatus("Sincronizado · sin sesiones nuevas en el cepillo", busy: false) }
                else if n > 0 { await setStatus("Sincronizado · \(n) \(n == 1 ? "sesión nueva" : "sesiones nuevas")", busy: false) }
                else { await setStatus("Sincronizado", busy: false) }
                connecting = false
                return
            } catch {
                /* Autosync al abrir: el cepillo suele estar dormido y tarda unos
                   segundos en anunciarse al levantarlo. Reintenta hasta 3 veces
                   (con pausa de 5s) antes de rendirse. La sincronización manual
                   falla a la primera, como siempre. */
                if auto, attempt < 3,
                   (error as? SyncError) == .notFound || (error as? SyncError) == .connectFailed {
                    dlog("autosync intento \(attempt) sin cepillo; reintento en 5s")
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    runWithStatus(known: known, auto: auto, attempt: attempt + 1)
                    return
                }
                switch error {
                case SyncError.notFound:
                    await setStatus("No apareció. Despierta el cepillo (levántalo) y reintenta", busy: false)
                    if !auto { await MainActor.run { self.offerScanAll = true } }
                    dlog("cepillo no encontrado (timeout escaneo)")
                case SyncError.connectFailed:
                    if UserDefaults.standard.string(forKey: savedBrushKey) != nil {
                        // Con id guardado el connect queda pendiente hasta que el
                        // cepillo despierta; si expira es que sigue dormido.
                        await setStatus("El cepillo está dormido. Levántalo y reintenta", busy: false)
                    } else {
                        await setStatus("Falló la sincronización. Reintenta con el cepillo cerca", busy: false)
                    }
                case SyncError.bluetoothOff:
                    await setStatus("Activa el Bluetooth del iPhone", busy: false)
                default:
                    await setStatus("Falló la sincronización. Reintenta con el cepillo cerca", busy: false)
                }
                connecting = false
            }
        }
    }

    private func runSync(known: CBPeripheral? = nil) async throws {
        await ready()
        guard central.state == .poweredOn else { throw SyncError.bluetoothOff }

        let p: CBPeripheral
        if let k = known { p = k } else { p = try await scan() }
        peripheral = p
        p.delegate = self
        try await connect(p)
        defer { central.cancelPeripheralConnection(p) }
        UserDefaults.standard.set(p.identifier.uuidString, forKey: savedBrushKey)
        dlog("conectado a \(p.name ?? "cepillo")")

        try await Task.sleep(nanoseconds: 2_000_000_000) // calentamiento GATT

        try await discover(p)
        dlog("servicios: \((p.services ?? []).map { $0.uuid.uuidString }.joined(separator: ","))")
        guard let svc = p.services?.first(where: { $0.uuid == SVC }) else {
            dlog("servicio principal NO encontrado")
            throw SyncError.connectFailed
        }
        try await discoverChars(svc, uuids: [C_WRITE, C_NOTIFY, C_SEND, C_RECV], on: p)
        if let bs = p.services?.first(where: { $0.uuid == BATT_SVC }) {
            try? await discoverChars(bs, uuids: [BATT_CHAR], on: p)
        }
        if let ds = p.services?.first(where: { $0.uuid == DIS_SVC }) {
            try? await discoverChars(ds, uuids: [DIS_MODEL], on: p)
        }

        t1Active = false; t1Buf = []; t1Expected = 0
        sessFetched = 0; lastHex = [:]

        // 1) Calibración de hora (0201 + 8 bytes -> fbb85) ANTES de suscribir:
        //    hay firmwares que solo habilitan los CCCD tras el primer comando.
        if let w = chars[C_WRITE] {
            let now = Date(); let cal = Calendar.current
            let dow = (cal.component(.weekday, from: now) + 6) % 7 // web: getDay()%7 (domingo=0)
            let pkt: [UInt8] = [0x02, 0x01,
                UInt8(cal.component(.year, from: now) - 2000), UInt8(cal.component(.month, from: now)),
                UInt8(cal.component(.day, from: now)), UInt8(cal.component(.hour, from: now)),
                UInt8(cal.component(.minute, from: now)), UInt8(cal.component(.second, from: now)),
                UInt8(cal.component(.weekday, from: now) - 1 < 0 ? 0 : (cal.component(.weekday, from: now) - 1) % 7), tzIndex()]
            _ = dow
            let okCal = try? await write(pkt, to: w, on: p)
            dlog("calibración hora -> fbb85: \(okCal == true ? "OK" : "error")")
        }

        // 2) Modelo (DIS), informativo
        if let mc = chars[DIS_MODEL], let mv = try? await read(mc, on: p) {
            let s = String(decoding: mv, as: UTF8.self).split(separator: "\0").first.map(String.init) ?? ""
            await MainActor.run { store?.model = s }
            dlog("modelo DIS: \(s)")
        } else {
            dlog("DIS no disponible")
        }

        // 3) Suscripciones: TODAS las notificables del servicio principal,
        //    con descubrimiento de descriptores (evidencia de si existe CCCD)
        var recvOK = false
        for c in (svc.characteristics ?? []) where c.properties.contains(.notify) || c.properties.contains(.indicate) {
            await describe(c, on: p)
            do {
                try await subscribe(c, on: p)
                dlog("subscribe \(short(c.uuid)) OK")
                if c.uuid == C_RECV { recvOK = true }
            } catch {
                dlog("subscribe \(short(c.uuid)) error: \(error.localizedDescription)")
            }
        }
        if let c = chars[BATT_CHAR] { try? await subscribe(c, on: p) }

        // 4) Comandos por fbb89
        if let send = chars[C_SEND] {
            try? await write([0x03, 0x03], to: send, on: p); try? await Task.sleep(nanoseconds: 150_000_000)
            try? await write([0x03, 0x02, 0x01], to: send, on: p); try? await Task.sleep(nanoseconds: 150_000_000)
            try? await write([0x03, 0x07], to: send, on: p); try? await Task.sleep(nanoseconds: 150_000_000)
            dlog("cmds 0303/0302/0307 enviados -> fbb89")
        }

        // 4r) Si fbb90 no suscribió: reintento tras los comandos y re-lanzamos 0307
        if !recvOK, let rc = chars[C_RECV] {
            do {
                try await subscribe(rc, on: p)
                dlog("subscribe fbb90 reintento OK")
                if let send = chars[C_SEND] {
                    try? await write([0x03, 0x07], to: send, on: p)
                    dlog("0307 re-enviado tras suscribir fbb90")
                }
            } catch {
                dlog("subscribe fbb90 reintento error: \(error.localizedDescription)")
            }
        }

        // 4c) Ajustes pendientes (standalone -> fbb85)
        if let w = chars[C_WRITE], let st = store {
            let pend = await MainActor.run { st.pending }
            if !pend.isEmpty {
                dlog("aplicando ajustes pendientes")
                var allOk = true
                if let scheme = pend.scheme, let pkts = buildSchemePackets(scheme) {
                    for pkt in pkts {
                        if !(await writeOK(pkt, to: w, on: p)) { allOk = false }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                    if allOk { await MainActor.run { st.brushMode = scheme } }
                }
                if let v = pend.areaRemind {
                    if await writeOK([0x02, 0x0d, v ? 1 : 0], to: w, on: p) { await MainActor.run { st.areaRemind = v } } else { allOk = false }
                }
                if let v = pend.remindSwitch {
                    if !(await writeOK([0x02, 0x39, v ? 1 : 0], to: w, on: p)) { allOk = false }
                }
                if let v = pend.runningSwitch {
                    if !(await writeOK([0x02, 0x40, v ? 1 : 0], to: w, on: p)) { allOk = false }
                }
                // Experimentales: valores acotados y reversibles; se anotan en el registro
                if let v = pend.wakeGesture {
                    let ok = await writeOK([0x02, 0x09, v ? 0x01 : 0xEC], to: w, on: p)
                    dlog("experimental gesto activacion -> \(v ? "01" : "EC"): \(ok ? "enviado" : "fallo")")
                    if !ok { allOk = false }
                }
                if let ms = pend.motorSpeed {
                    let v = max(0, min(100, ms))
                    let ok = await writeOK([0x02, 0x07, 0, 0, UInt8((v >> 8) & 0xff), UInt8(v & 0xff)], to: w, on: p)
                    dlog("experimental velocidad motor -> \(v): \(ok ? "enviado" : "fallo")")
                    if !ok { allOk = false }
                }
                if let v = pend.overPressure {
                    if await writeOK([0x02, 0x12, v ? 1 : 0], to: w, on: p) { await MainActor.run { st.overPressure = v } } else { allOk = false }
                }
                if let hd = pend.headDays {
                    let v = max(1, min(365, hd))
                    if await writeOK([0x02, 0x17, UInt8((v >> 8) & 0xff), UInt8(v & 0xff)], to: w, on: p) { await MainActor.run { st.headDays = v } } else { allOk = false }
                }
                if pend.resetHead == true {
                    if await writeOK([0x02, 0x0f], to: w, on: p) { await MainActor.run { st.headTimes = 0 } } else { allOk = false }
                }
                if allOk { await MainActor.run { st.pending = PendingSettings(); st.save() }; dlog("ajustes aplicados") }
                else { dlog("algunos ajustes no se pudieron enviar; quedan pendientes") }

                // 4d) Verificacion REAL: releer el estado del cepillo (0302) y confirmar
                // que cada ajuste quedo como lo pedimos. Si el cepillo no lo confirma,
                // el ajuste no es real para ese modelo y lo decimos.
                if let send = chars[C_SEND] {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    try? await write([0x03, 0x02, 0x01], to: send, on: p)
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    let cur = await MainActor.run { (st.brushMode, st.areaRemind, st.overPressure, st.headDays, st.headTimes) }
                    var checks: [String] = []
                    if let scheme = pend.scheme { checks.append(cur.0 == scheme ? "modo OK" : "modo NO confirmado por el cepillo") }
                    if let v = pend.areaRemind { checks.append(cur.1 == v ? "aviso zonas OK" : "aviso zonas NO confirmado") }
                    if let v = pend.overPressure { checks.append(cur.2 == v ? "alerta presion OK" : "alerta presion NO confirmada") }
                    if let hd = pend.headDays { checks.append(cur.3 == max(1, min(365, hd)) ? "dias cabezal OK" : "dias cabezal NO confirmado") }
                    if pend.resetHead == true { checks.append(cur.4 == 0 ? "reinicio cabezal OK" : "reinicio cabezal NO confirmado") }
                    if !checks.isEmpty {
                        let rep = checks.joined(separator: " - ")
                        dlog("verificacion de ajustes: \(rep)")
                        await MainActor.run { st.settingsCheck = rep }
                    }
                }
            }
        }

        // 5) Espera de sesiones (8s) y enriquecimiento
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sessSignal = c
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let s = sessSignal { sessSignal = nil; s.resume() }
            }
        }
        if t1Active { flushT1() }
        await MainActor.run { store?.lastSess = sessFetched }
        dlog("espera terminada; sesiones recibidas esta sync: \(sessFetched)")
        try? await Task.sleep(nanoseconds: 1_500_000_000) // pushes 0000/2604/5a00 llegan después

        // 6) Batería estándar BLE
        if let bc = chars[BATT_CHAR], let bv = try? await read(bc, on: p), bv.count > 0 {
            await MainActor.run { store?.battery = Int(bv[0]) }
            dlog("batería 0x2A19: \(Int(bv[0]))%")
        } else {
            dlog("batería 0x2A19 no leída")
        }

        await MainActor.run {
            store?.lastSync = Date().timeIntervalSince1970 * 1000
            store?.sortSessions(); store?.save()
        }
        dlog("--- sync fin ---")
    }

    private func short(_ u: CBUUID) -> String { String(u.uuidString.suffix(5)).lowercased() }

    private func describe(_ c: CBCharacteristic, on p: CBPeripheral) async {
        do {
            try await discoverDesc(c, on: p)
            let ds = (c.descriptors ?? []).map { $0.uuid.uuidString }.joined(separator: ",")
            dlog("desc \(short(c.uuid)): [\(ds)]")
        } catch {
            dlog("desc \(short(c.uuid)) error: \(error.localizedDescription)")
        }
    }

    private func discoverDesc(_ c: CBCharacteristic, on p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            descCont[c.uuid] = cont
            p.discoverDescriptors(for: c)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let k = descCont[c.uuid] { descCont[c.uuid] = nil; k.resume(throwing: SyncError.connectFailed) }
            }
        }
    }

    private func writeOK(_ bytes: [UInt8], to c: CBCharacteristic, on p: CBPeripheral) async -> Bool {
        (try? await write(bytes, to: c, on: p)) != nil
    }

    private func tzIndex() -> UInt8 {
        let off = TimeZone.current.secondsFromGMT() / 60
        var best = 0
        for i in 1..<TZ_MIN.count where abs(TZ_MIN[i] - off) < abs(TZ_MIN[best] - off) { best = i }
        return UInt8(best + 1)
    }

    /* ---------- Escaneo / conexión / descubrimiento ---------- */

    private let savedBrushKey = "oclean.savedBrushID"

    private func scan() async throws -> CBPeripheral {
        // Si iOS ya lo tiene conectado (p. ej. la app oficial), úsalo directo
        if let p = central.retrieveConnectedPeripherals(withServices: [SVC]).first {
            dlog("cepillo ya conectado por el sistema: \(p.name ?? "?")")
            return p
        }
        // Reconexión directa por identificador guardado: sin escanear.
        if let idStr = UserDefaults.standard.string(forKey: savedBrushKey),
           let uuid = UUID(uuidString: idStr),
           let p = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            dlog("cepillo recuperado por id guardado, sin escanear")
            return p
        }
        // El cepillo no anuncia el UUID 128-bit en el paquete de advertising:
        // escaneamos sin filtro y lo reconocemos por nombre "Oclean" o servicio anunciado.
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CBPeripheral, Error>) in
            scanCont = cont
            Task { @MainActor in self.candidates = [] }
            self.candidatesStore = [:]
            central.scanForPeripherals(withServices: nil, options: nil)
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if let c = scanCont {
                    scanCont = nil
                    central.stopScan()
                    c.resume(throwing: SyncError.notFound)
                }
            }
        }
    }

    private func connect(_ p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connectCont = cont
            central.connect(p, options: nil)
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if let c = connectCont {
                    connectCont = nil
                    c.resume(throwing: SyncError.connectFailed)
                }
            }
        }
    }

    private func discover(_ p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            servicesCont = cont
            p.discoverServices([SVC, BATT_SVC, DIS_SVC])
        }
    }

    private func discoverChars(_ s: CBService, uuids: [CBUUID], on p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            charsCont[s.uuid] = cont
            p.discoverCharacteristics(uuids, for: s)
        }
    }

    private func subscribe(_ c: CBCharacteristic, on p: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            notifyCont[c.uuid] = cont
            p.setNotifyValue(true, for: c)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let k = notifyCont[c.uuid] { notifyCont[c.uuid] = nil; k.resume(throwing: SyncError.connectFailed) }
            }
        }
    }

    private func write(_ bytes: [UInt8], to c: CBCharacteristic, on p: CBPeripheral) async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            writeCont[c.uuid] = cont
            p.writeValue(Data(bytes), for: c, type: .withResponse)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let k = writeCont[c.uuid] { writeCont[c.uuid] = nil; k.resume(throwing: SyncError.connectFailed) }
            }
        }
        return true
    }

    private func read(_ c: CBCharacteristic, on p: CBPeripheral) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            readCont[c.uuid] = cont
            p.readValue(for: c)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let k = readCont[c.uuid] { readCont[c.uuid] = nil; k.resume(throwing: SyncError.connectFailed) }
            }
        }
    }

    /* ---------- Protocolo (port de dispatch/flushT1 de app.js) ---------- */

    private func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02x", $0) }.joined() }

    private func dispatch(_ d: [UInt8], isRecv: Bool) {
        if isRecv && t1Active {
            t1Buf.append(contentsOf: d)
            if t1Buf.count >= t1Expected { flushT1() }
            return
        }
        let h = hex(d), key = isRecv ? "f90" : "f86"
        if h == lastHex[key] { return }
        lastHex[key] = h
        if d.count < 2 { return }
        let prefix = (Int(d[0]) << 8) | Int(d[1])
        let pay = Array(d.dropFirst(2))

        if prefix == 0x0307 && d.count >= 8 && d[2] == 0x2a && d[3] == 0x42 && d[4] == 0x23 {
            // Cabecera *B#
            let count = (Int(d[5]) << 8) | Int(d[6])
            let inline = Array(d.dropFirst(7))
            if count > 0 {
                t1Active = true; t1Buf = inline; t1Expected = count * 42
                if t1Buf.count >= t1Expected { flushT1() }
            } else if inline.count >= 11 {
                let y0 = Int(inline[0]) + 2000
                if y0 >= 2020 {
                    var comps = DateComponents()
                    comps.year = y0; comps.month = Int(inline[1]); comps.day = Int(inline[2])
                    comps.hour = Int(inline[3]); comps.minute = Int(inline[4]); comps.second = Int(inline[5])
                    if let date = Calendar.current.date(from: comps) {
                        let sched0 = (Int(inline[7]) << 8) | Int(inline[8])
                        let valid0 = (Int(inline[9]) << 8) | Int(inline[10])
                        var dur0: Int? = nil
                        if valid0 > 0 && (sched0 == 0 || valid0 <= sched0) { dur0 = valid0 } else if sched0 > 0 { dur0 = sched0 }
                        let s = BrushSession(ts: date.timeIntervalSince1970 * 1000, pnum: Int(inline[6]),
                                             dur: dur0, durSched: sched0 > 0 ? sched0 : nil, score: nil, zones: nil, coverage: nil, sample: nil)
                        Task { @MainActor in
                            if self.store?.mergeSession(s) == true { self.sessFetched += 1 }
                            self.store?.sortSessions()
                        }
                        signalSess()
                    }
                }
            }
            return
        }
        if prefix == 0x0303 { // estado: batería en pay[3]
            if pay.count >= 4 && pay[3] <= 100 { Task { @MainActor in self.store?.battery = Int(pay[3]) } }
            return
        }
        if prefix == 0x0302 { // ajustes
            if pay.count >= 1 && pay[0] <= 100 { Task { @MainActor in self.store?.battery = Int(pay[0]) } }
            if pay.count >= 32 {
                Task { @MainActor in
                    self.store?.headDays = (Int(pay[29]) << 8) | Int(pay[30])
                    self.store?.headTimes = Int(pay[31])
                    self.store?.brushMode = Int(pay[5])
                    self.store?.overPressure = pay[8] != 0
                    self.store?.areaRemind = pay[23] != 0
                }
            }
            return
        }
        if prefix == 0x0000 { // push de puntuación
            if pay.count >= 1 && pay[0] != 0xff && pay[0] <= 100 {
                Task { @MainActor in
                    if var s = self.store?.newestSession() {
                        s.score = Int(pay[0]); _ = self.store?.mergeSession(s)
                    }
                }
            }
            return
        }
        if prefix == 0x2604 { // push de zonas
            if pay.count >= 14 {
                let areas = Array(pay[6..<14]).map(Int.init)
                Task { @MainActor in
                    if var s = self.store?.newestSession() {
                        s.zones = areas
                        s.coverage = Int((Double(areas.filter { $0 > 100 }.count) / 8.0 * 100.0).rounded())
                        _ = self.store?.mergeSession(s)
                    }
                }
            }
            return
        }
        if prefix == 0x5a00 { // metadatos de sesión
            if pay.count >= 18 {
                let y = Int(pay[7]) + 2000
                if y >= 2020 {
                    var comps = DateComponents()
                    comps.year = y; comps.month = Int(pay[8]); comps.day = Int(pay[9])
                    comps.hour = Int(pay[10]); comps.minute = Int(pay[11]); comps.second = Int(pay[12])
                    if let date = Calendar.current.date(from: comps) {
                        let dur = pay[15] != 0xff ? Int(pay[15]) : nil
                        let s = BrushSession(ts: date.timeIntervalSince1970 * 1000, pnum: nil, dur: dur,
                                             durSched: nil, score: nil, zones: nil, coverage: nil, sample: nil)
                        Task { @MainActor in _ = self.store?.mergeSession(s); self.store?.sortSessions() }
                        signalSess()
                    }
                }
            }
            return
        }
        if prefix == 0x0308 { // respuesta INFO
            if let rec = parseSessionRecord(pay) {
                Task { @MainActor in _ = self.store?.mergeSession(rec); self.store?.sortSessions() }
                signalSess()
            }
            return
        }
    }

    private func flushT1() {
        let buf = t1Buf
        t1Active = false; t1Buf = []; t1Expected = 0
        let n = buf.count / 42
        for i in 0..<n {
            if let rec = parseSessionRecord(Array(buf[i*42..<(i+1)*42])) {
                Task { @MainActor in _ = self.store?.mergeSession(rec) }
                sessFetched += 1
                signalSess()
            }
        }
        Task { @MainActor in self.store?.sortSessions() }
    }

    private func signalSess() {
        if let s = sessSignal { sessSignal = nil; s.resume() }
    }
}

/* ---------- Delegados ---------- */
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .unknown, let c = centralReady { centralReady = nil; c.resume() }
        if central.state == .poweredOff {
            if let c = scanCont { scanCont = nil; c.resume(throwing: SyncError.bluetoothOff) }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let advSvc = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let isOclean = name.lowercased().contains("oclean") || advSvc.contains(SVC)
        if !name.isEmpty {
            candidatesStore[p.identifier] = p
            Task { @MainActor in
                if !self.candidates.contains(where: { $0.id == p.identifier }) {
                    self.candidates.append(BleCandidate(id: p.identifier, name: name))
                }
            }
        }
        guard let c = scanCont, isOclean else { return }
        scanCont = nil
        central.stopScan()
        dlog("encontrado: \(name.isEmpty ? p.identifier.uuidString : name)")
        c.resume(returning: p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        if let c = connectCont { connectCont = nil; c.resume() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if let c = connectCont { connectCont = nil; c.resume(throwing: SyncError.connectFailed) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // nada: la UI vuelve a "sin conectar" por estado
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let c = servicesCont {
            servicesCont = nil
            if let e = error { c.resume(throwing: e) } else { c.resume() }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] { chars[c.uuid] = c }
        if let c = charsCont[service.uuid] {
            charsCont[service.uuid] = nil
            if let e = error { c.resume(throwing: e) } else { c.resume() }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor c: CBCharacteristic, error: Error?) {
        if let k = descCont[c.uuid] {
            descCont[c.uuid] = nil
            if let e = error { k.resume(throwing: e) } else { k.resume() }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let k = notifyCont[c.uuid] {
            notifyCont[c.uuid] = nil
            if let e = error { k.resume(throwing: e) } else { k.resume() }
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let k = writeCont[c.uuid] {
            writeCont[c.uuid] = nil
            if let e = error { k.resume(throwing: e) } else { k.resume() }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let v = c.value else {
            if let k = readCont[c.uuid] { readCont[c.uuid] = nil; k.resume(throwing: SyncError.connectFailed) }
            return
        }
        if let k = readCont[c.uuid] {
            readCont[c.uuid] = nil
            k.resume(returning: v)
            return
        }
        let d = [UInt8](v)
        if c.uuid == BATT_CHAR { Task { @MainActor in self.store?.battery = Int(d.first ?? 0) }; return }
        if !(t1Active && c.uuid == C_RECV) {
            let preview = d.count > 20 ? hex(Array(d.prefix(20))) + "…" : hex(d)
            dlog("notif \(short(c.uuid)) [\(d.count)B]: \(preview)")
        }
        dispatch(d, isRecv: c.uuid == C_RECV)
    }
}
