import SwiftUI
import UniformTypeIdentifiers

struct AjustesView: View {
    @EnvironmentObject var store: BrushStore
    @EnvironmentObject var ble: BLEManager

    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var showImporter = false
    @State private var showWipeConfirm = false
    @State private var notice: String? = nil
    @State private var copied = false
    @State private var showHeadConfirm = false

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ajustes").font(.largeTitle.bold()).padding(.top, 8)

                    // Opciones de cepillado: las 4 del menú del cepillo
                    // (petición de Adrián 11:29): duración, cambio de zona, modo
                    // y potencia, más el botón de cambio de cabezal al final
                    // (pedido de Adrián 02:03, 13-nov). Modo+potencia+duración se
                    // componen en un único programa de fábrica vía 0206 y se envían
                    // al sincronizar.
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Opciones de cepillado").font(.headline)
                                if !store.pending.isEmpty {
                                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Duración del cepillado").font(.subheadline)
                                Picker("Duración", selection: Binding(
                                    get: { store.ajDuration },
                                    set: { store.setAjustes(duration: $0) })) {
                                    Text("2 min").tag(120)
                                    Text("2:30").tag(150)
                                    Text("3 min").tag(180)
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Modo").font(.subheadline)
                                Picker("Modo", selection: Binding(
                                    get: { store.ajMode },
                                    set: { store.setAjustes(mode: $0) })) {
                                    Text("Limpiar").tag(0)
                                    Text("Blanquear").tag(1)
                                    Text("Masajear").tag(2)
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Potencia de cepillado").font(.subheadline)
                                    Spacer()
                                    Text("\(store.ajPower)").foregroundColor(.secondary).font(.subheadline.weight(.semibold))
                                }
                                // 1-32 en Limpiar, 1-4 en Blanquear/Masajear (como el cepillo)
                                Slider(value: Binding(
                                    get: { Double(store.ajPower) },
                                    set: { store.setAjustes(power: Int($0)) }), in: 1...Double(maxPower(for: store.ajMode)), step: 1)
                                    .tint(Theme.accent)
                            }

                            Toggle("Cambio de zona", isOn: Binding(
                                get: { store.pending.areaRemind ?? store.areaRemind },
                                set: { store.setAreaRemind($0) })).tint(Theme.accent)

                            Text("Los cambios se envían al cepillo en la próxima sincronización y se comprueban contra su estado real.")
                                .font(.footnote).foregroundColor(.secondary)
                            if let chk = store.settingsCheck {
                                Text("Verificación con el cepillo: \(chk)")
                                    .font(.caption).foregroundColor(.secondary)
                            }

                            // Cambio de cabezal (pedidos de Adrián 02:03 y voz
                            // 02:56, 13-nov): recordatorio LOCAL, cuenta atrás de
                            // 90 días independiente del cepillo; "Cambiar" la
                            // reinicia a 90 al instante, sin sincronizar.
                            Divider().padding(.vertical, 2)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cambio de cabezal").font(.subheadline)
                                    Text(headLabel).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Cambiar") { withAnimation { showHeadConfirm.toggle() } }
                                    .glassGhostButton()
                            }
                            // Confirmación en línea, JUSTO debajo del botón
                            // (pedido de Adrián 09:37, 13-nov): el diálogo del
                            // sistema salía como hoja abajo del todo, lejos del
                            // botón. Así aparece pegado donde pulsa.
                            if showHeadConfirm {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("¿Has puesto un cabezal nuevo? La cuenta atrás vuelve a 90 días.")
                                        .font(.footnote).foregroundColor(.secondary)
                                    HStack(spacing: 10) {
                                        Button("Cambiar cabezal") {
                                            store.changeHeadNow()
                                            withAnimation { showHeadConfirm = false }
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
                                        .accessibilityIdentifier("head-confirm-change")
                                        Button("Cancelar") { withAnimation { showHeadConfirm = false } }
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .accessibilityIdentifier("head-confirm")
                            }
                        }
                    }

                    // Datos
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Datos").font(.headline)
                            HStack {
                                Text("Exportar historial")
                                Spacer()
                                Button("Exportar") { export() }.glassGhostButton()
                            }
                            HStack {
                                Text("Restaurar historial")
                                Spacer()
                                Button("Elegir archivo") { showImporter = true }.glassGhostButton()
                            }
                            HStack {
                                Text("Borrar todo")
                                Spacer()
                                Button("Borrar") { showWipeConfirm = true }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                            }
                        }
                    }

                    // Cepillo
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cepillo").font(.headline)
                            HStack {
                                Text("Modelo").foregroundColor(.secondary)
                                Spacer()
                                Text(store.model ?? "—")
                            }.font(.subheadline)

                            Text("Si usas también la app oficial de Oclean, sincroniza primero aquí: la oficial puede vaciar la memoria del cepillo al conectar.")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }

                    // Diagnóstico
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Diagnóstico").font(.headline)
                            ScrollView {
                                Text(ble.fullLogText.isEmpty ? "Sin registro todavía." : ble.fullLogText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                            HStack {
                                Text("Registro de conexión").foregroundColor(.secondary).font(.subheadline)
                                Spacer()
                                Button(copied ? "Copiado ✓" : "Copiar") {
                                    UIPasteboard.general.string = ble.fullLogText
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                                }.glassGhostButton()
                            }
                            Text("Si algo no funciona, copia este registro y envíaselo a Instinct.")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }

                    if let n = notice {
                        Text(n).font(.footnote).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    VStack(spacing: 6) {
                        Text("Oclean X · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                            .font(.footnote).foregroundColor(.secondary)
                        Text("Modelo 3D: BodyParts3D / Anatomography © DBCLS, adaptado por OrganUI y aquí (raíces recortadas, boca abierta, colores) · CC BY-SA 2.1 JP")
                            .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showShare) {
            if let u = shareURL { ShareSheet(url: u) }
        }
        .onAppear {
            // Para la captura de CI: abre la confirmación en línea del cabezal.
            if ProcessInfo.processInfo.arguments.contains("-showHeadConfirm") { showHeadConfirm = true }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.json]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url) {
                    let n = store.importData(d)
                    notice = n >= 0 ? "Historial restaurado (\(n) nuevos)" : "Ese archivo no vale"
                } else {
                    notice = "Ese archivo no vale"
                }
            }
        }
        .confirmationDialog("¿Borrar todo? Se eliminan historial y ajustes guardados.", isPresented: $showWipeConfirm, titleVisibility: .visible) {

            Button("Borrar todo", role: .destructive) { store.wipe(); ble.clearLog(); notice = "Datos borrados" }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var headLabel: String {
        /* Recordatorio local (voz de Adrián 02:56, 13-nov): tiempo RESTANTE. */
        if let left = store.headRemaining {
            return left > 0 ? "Quedan \(left) días" : "Toca cambiar cabezal"
        }
        return "Pulsa Cambiar cuando pongas uno nuevo"
    }

    private func export() {
        guard let d = store.exportData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mi-cepillo-historial.json")
        try? d.write(to: url)
        shareURL = url
        showShare = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
