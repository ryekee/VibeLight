import SwiftUI

/// Page-scope header above a grouped box (e.g. "Session", "Interactions").
struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// One row inside a grouped box: title (+ optional description) on the left,
/// control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder var control: () -> Control

    init(_ title: String, description: String? = nil,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

/// Container that wraps a set of rows in a rounded grouped box.
struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A header centered above the page content (icon + page title).
struct SettingsPageHeader: View {
    let destination: SettingsDestination
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: destination.systemImage)
                .font(.title2)
                .foregroundStyle(destination.tint)
                .frame(width: 26, height: 26)
            Text(destination.label).font(.title2).bold()
        }
        .padding(.bottom, 8)
    }
}
