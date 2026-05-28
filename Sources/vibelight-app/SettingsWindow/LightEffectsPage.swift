import SwiftUI
import VibeBrokerCore

struct LightEffectsPage: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionBox(
                header: "Session",
                states: [.idle, .working, .done],
                description: { state in
                    switch state {
                    case .idle:    return "No agent active."
                    case .working: return "Agent is thinking or running a tool."
                    case .done:    return "Agent finished its turn."
                    default:       return ""
                    }
                }
            )
            sectionBox(
                header: "Interactions",
                states: [.waitingInput, .needsAuth],
                description: { state in
                    switch state {
                    case .waitingInput: return "Agent is waiting for your input."
                    case .needsAuth:    return "Agent needs your permission."
                    default:            return ""
                    }
                }
            )
            sectionBox(
                header: "System",
                states: [.compacting, .error],
                description: { state in
                    switch state {
                    case .compacting: return "Context window is being compressed."
                    case .error:      return "Tool call failed or agent reported an error."
                    default:          return ""
                    }
                }
            )

            HStack {
                Spacer()
                Button("Reset to defaults") { viewModel.settings.resetColors() }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func sectionBox(header: String,
                             states: [VibeBrokerCore.State],
                             description: @escaping (VibeBrokerCore.State) -> String) -> some View {
        SettingsSectionHeader(title: header)
        SettingsBox {
            ForEach(Array(states.enumerated()), id: \.element) { idx, state in
                row(for: state, description: description(state))
                if idx < states.count - 1 { Divider().padding(.horizontal, 12) }
            }
        }
    }

    private func row(for state: VibeBrokerCore.State, description: String) -> some View {
        SettingsRow(StateAppearance.label(state), description: description) {
            HStack(spacing: 8) {
                ColorPicker("", selection: bindingForColor(state)).labelsHidden().frame(width: 36)
                Slider(value: bindingForBrightness(state), in: 1...255, step: 1).frame(width: 120)
                Text("\(Int(viewModel.settings.colors[state]?.brightness ?? 0))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
                Picker("", selection: bindingForEffect(state)) {
                    ForEach([Effect.solid, .breathe, .blink, .blinkThenSolid], id: \.self) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private func bindingForColor(_ state: VibeBrokerCore.State) -> Binding<Color> {
        Binding(
            get: {
                let rgb = viewModel.settings.colors[state]?.rgb ?? [0, 0, 0]
                return Color(red: Double(rgb[0]) / 255,
                             green: Double(rgb[1]) / 255,
                             blue: Double(rgb[2]) / 255)
            },
            set: { newColor in
                let rgb = newColor.rgbComponents()
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: rgb, brightness: current.brightness, effect: current.effect)
                viewModel.settings.colors[state] = current
            }
        )
    }

    private func bindingForBrightness(_ state: VibeBrokerCore.State) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.colors[state]?.brightness ?? 0) },
            set: { newValue in
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: current.rgb, brightness: Int(newValue), effect: current.effect)
                viewModel.settings.colors[state] = current
            }
        )
    }

    private func bindingForEffect(_ state: VibeBrokerCore.State) -> Binding<Effect> {
        Binding(
            get: { viewModel.settings.colors[state]?.effect ?? .solid },
            set: { newEffect in
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: current.rgb, brightness: current.brightness, effect: newEffect)
                viewModel.settings.colors[state] = current
            }
        )
    }
}

private extension Color {
    func rgbComponents() -> [Int] {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return [
            Int(ns.redComponent * 255),
            Int(ns.greenComponent * 255),
            Int(ns.blueComponent * 255),
        ]
    }
}
