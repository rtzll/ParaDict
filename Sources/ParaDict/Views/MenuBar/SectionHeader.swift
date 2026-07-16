import SwiftUI

struct SectionHeader: View {
  let title: String
  let icon: String
  var iconColor: Color = .secondary

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.caption)
        .foregroundColor(iconColor)
        .accessibilityHidden(true)
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
    }
  }
}
