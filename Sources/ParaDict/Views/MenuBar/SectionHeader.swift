import SwiftUI

struct SectionHeader: View {
  let title: String
  let icon: String
  var iconColor: Color = .secondary

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11))
        .foregroundColor(iconColor)
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
    }
  }
}
