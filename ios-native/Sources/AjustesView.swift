import SwiftUI

struct AjustesView: View {
    @EnvironmentObject var store: BrushStore
    @State private var headDaysInput: String = ""

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ajustes").font(.largeTitle.bold()).padding(.top, 8)

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cepillo").font(.headline)
                            row("Modelo", store.model ?? "—")
                            row("Batería", store.battery.map { "\($0)%" } ?? "—")
                            row("Cabezal", store.headDays.map { "\($0) días" } ?? "—")
                            row("Usos del cabezal", store.headTimes.map { "\($0)" } ?? "—")
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Programa de cepillado").font(.headline)
                            Picker("Programa", selection: Binding(
                                get: { store.pending.scheme ?? store.brushMode ?? 0 },
                                set: { store.pending.scheme = $0; store.save() })) {
                                ForEach(SCHEMES.keys.sorted(), id: \.self) { k in
                                    Text(SCHEMES[k]!.0).tag(k)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.accent)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Avisos").font(.headline).padding(.bottom, 6)
                            Toggle("Aviso de zonas", isOn: Binding(
                                get: { store.pending.areaRemind ?? store.areaRemind },
                                set: { store.pending.areaRemind = $0; store.save() })).tint(Theme.accent)
                            Toggle("Aviso de tiempo", isOn: Binding(
                                get: { store.pending.remindSwitch ?? false },
                                set: { store.pending.remindSwitch = $0; store.save() })).tint(Theme.accent)
                            Toggle("Alerta de presión", isOn: Binding(
                                get: { store.pending.overPressure ?? store.overPressure },
                                set: { store.pending.overPressure = $0; store.save() })).tint(Theme.accent)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cabezal").font(.headline)
                            HStack {
                                TextField("Días de aviso", text: $headDaysInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                Button("Guardar") {
                                    if let v = Int(headDaysInput) { store.pending.headDays = v; store.save() }
                                }.tint(Theme.accent)
                            }
                            Button("Reiniciar contador de cabezal") {
                                store.pending.resetHead = true; store.save()
                            }.tint(Theme.accent)
                        }
                    }

                    if !store.pending.isEmpty {
                        Text("Los cambios se envían al cepillo en la próxima sincronización.")
                            .font(.footnote).foregroundColor(.secondary)
                    }

                    VStack(spacing: 6) {
                        Text("Oclean X · app no oficial").font(.footnote).foregroundColor(.secondary)
                        Text("Modelo 3D: organui (CC BY-SA), modificado.").font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }.font(.subheadline)
    }
}
