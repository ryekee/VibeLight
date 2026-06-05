import SwiftUI
import VibeBrokerCore

enum StateAppearance {
    /// Maps a logical state to a menubar-icon color. Mirrors spec §2 (light colors;
    /// the menubar icon is a static colored circle — animations live on the real light).
    static func color(_ state: VibeBrokerCore.State) -> Color {
        switch state {
        case .idle, .done:    return Color(red: 0.31, green: 0.12, blue: 0.47) // purple
        case .working:        return Color(red: 0.16, green: 0.47, blue: 1.00) // blue
        case .compacting:     return Color(red: 0.94, green: 0.86, blue: 0.24) // yellow
        case .waitingInput:   return Color(red: 1.00, green: 0.55, blue: 0.12) // orange
        case .needsAuth,
             .error:          return Color(red: 1.00, green: 0.12, blue: 0.12) // red
        }
    }

    /// Colored emoji dot mirroring `color(_:)`. Used in the menu's text rows
    /// because the macOS `.menu` style can't reliably tint custom RGB swatches,
    /// whereas emoji always render in color.
    static func swatch(_ state: VibeBrokerCore.State) -> String {
        switch state {
        case .idle, .done:    return "🟣" // purple
        case .working:        return "🔵" // blue
        case .compacting:     return "🟡" // yellow
        case .waitingInput:   return "🟠" // orange
        case .needsAuth,
             .error:          return "🔴" // red
        }
    }

    /// Short human label shown in the status row of the menu.
    static func label(_ state: VibeBrokerCore.State) -> String {
        switch state {
        case .idle:          return "Idle"
        case .done:          return "Done"
        case .working:       return "Working"
        case .compacting:    return "Compacting"
        case .waitingInput:  return "Waiting for input"
        case .needsAuth:     return "Needs your approval"
        case .error:         return "Error"
        }
    }
}
