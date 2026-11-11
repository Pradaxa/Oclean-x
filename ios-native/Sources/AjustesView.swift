import SwiftUI
import UniformTypeIdentifiers

struct AjustesView: View {
    @EnvironmentObject var store: BrushStore
    @EnvironmentObject var ble: BLEManager

    @State private var headDaysInput: String = ""
    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var showImporter = false
    @State private var showWipeConfirm = false
    @State private var notice: String? = nil
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ajustes").font(.largeTitle.bold()).padding(.top, 8)

                    // Opciones de cepillado
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Opciones de cepillado").font(.headline)
                                if !store.pending.isEmpty {
                                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                                }
                            }

                            HStack {
                                Text("Modo de cepillado")
                                Spacer(minLength: 24)
                                Picker("Modo", selection: Binding(
                                    get: { store.pending.scheme ?? store.brushMode ?? 0 },
                                    set: { store.pending.scheme = $0; store.save() })) {
                                    ForEach(SCHEMES.keys.sorted(), id: \.self) { k in
                                        Text(SCHEMES[k]!.0).lineLimit(1).tag(k)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.accent)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false) // no partir el nombre del modo en dos líneas
                            }

                            Toggle("Aviso de zonas", isOn: Binding(
                                get: { store.pending.areaRemind ?? store.areaRemind },
                                set: { store.pending.areaRemind = $0; store.save() })).tint(Theme.accent)
                            Toggle("Aviso de tiempo", isOn: Binding(
                                get: { store.pending.remindSwitch ?? false },
                                set: { store.pending.remindSwitch = $0; store.save() })).tint(Theme.accent)
                            Toggle("Alerta de presión", isOn: Binding(
                                get: { store.pending.overPressure ?? store.overPressure },
                                set: { store.pending.overPressure = $0; store.save() })).tint(Theme.accent)

                            Divider().background(Color.white.opacity(0.08))

                            HStack {
                                Text("Días de vida del cabezal")
                                Spacer()
                                TextField("90", text: $headDaysInput)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 64)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                                Button("Aplicar") {
                                    if let v = Int(headDaysInput), v >= 1, v <= 365 {
                                        store.pending.headDays = v; store.save()
                                        notice = "Se aplicará en la próxima sincronización"
                                    }
                                }.glassGhostButton()
                            }
                            HStack {
                                Text("Reiniciar contador de cabezal")
                                Spacer()
                                Button("Reiniciar") {
                                    store.pending.resetHead = true; store.save()
                                    notice = "Se aplicará en la próxima sincronización"
                                }.glassGhostButton()
                            }

                            Text("Los cambios se envían al cepillo en la próxima sincronización y se comprueban contra su estado real. Potencia y duración vienen definidas por el modo elegido.")
                                .font(.footnote).foregroundColor(.secondary)
                            if let chk = store.settingsCheck {
                                Text("Verificación con el cepillo: \(chk)")
                                    .font(.caption).foregroundColor(.secondary)
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
