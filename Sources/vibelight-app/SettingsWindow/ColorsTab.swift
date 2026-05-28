import SwiftUI
import VibeBrokerCore

struct ColorsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack {
            ScrollView {
                ForEach(VibeBrokerCore.State.allCases, id: \.self) { state in
                    HStack {
                        Text(StateAppearance.label(state))
                            .frame(width: 160, alignment: .leading)
                        ColorPicker("", selection: bindingForColor(state))
                            .frame(width: 60)
                        Slider(
                            value: bindingForBrightness(state),
                            in: 1...255,
                            step: 1
                        ) {
                            Text("Brightness")
                        }
                        .frame(width: 160)
                        Text("\(Int(viewModel.settings.colors[state]?.brightness ?? 0))")
                            .frame(width: 40)
                        Picker("", selection: bindingForEffect(state)) {
                            ForEach([Effect.solid, .breathe, .blink, .blinkThenSolid], id: \.self) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .frame(width: 140)
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Reset to defaults") { viewModel.settings.resetColors() }
            }
        }
        .padding()
    }

    private func bindingForColor(_ state: VibeBrokerCore.State) -> Binding<Color> {
        Binding(
            get: {
                let rgb = viewModel.settings.colors[state]?.rgb ?? [0, 0, 0]
                return Color(
                    red: Double(rgb[0]) / 255,
                    green: Double(rgb[1]) / 255,
                    blue: Double(rgb[2]) / 255
                )
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
