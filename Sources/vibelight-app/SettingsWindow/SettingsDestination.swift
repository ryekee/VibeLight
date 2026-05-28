import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case general
    case integrations
    case lightEffects
    case network
    case scenePack
    case diagnostics
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:      return "General"
        case .integrations: return "Integrations"
        case .lightEffects: return "Light Effects"
        case .network:      return "Network"
        case .scenePack:    return "Scene Pack"
        case .diagnostics:  return "Diagnostics"
        case .about:        return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "gear"
        case .integrations: return "rectangle.connected.to.line.below"
        case .lightEffects: return "lightbulb.fill"
        case .network:      return "wifi"
        case .scenePack:    return "rectangle.stack.fill"
        case .diagnostics:  return "wrench.and.screwdriver.fill"
        case .about:        return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general:      return .gray
        case .integrations: return .blue
        case .lightEffects: return .yellow
        case .network:      return .green
        case .scenePack:    return .purple
        case .diagnostics:  return .orange
        case .about:        return .blue
        }
    }

    /// Sidebar grouping. `nil` puts the item in the unlabeled top group.
    var group: String? {
        switch self {
        case .general, .integrations, .lightEffects, .network: return nil
        case .scenePack, .diagnostics:                          return "Advanced"
        case .about:                                            return "VibeLight"
        }
    }
}
