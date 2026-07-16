import SwiftUI

struct PermissionsBanner: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionHeader(
        title: "Permissions Needed", icon: "exclamationmark.shield.fill", iconColor: .orange)

      VStack(spacing: 4) {
        if !viewModel.snapshot.accessibilityGranted {
          PermissionRow(
            icon: "keyboard",
            label: "Accessibility",
            detail: "Required for global hotkeys"
          ) {
            viewModel.openAccessibilitySettings()
          }
        }

        if !viewModel.snapshot.microphoneGranted {
          PermissionRow(
            icon: "mic.slash",
            label: "Microphone",
            detail: "Required for recording"
          ) {
            Task { await viewModel.requestMicrophone() }
          }
        }
      }
    }
  }
}

private struct PermissionRow: View {
  let icon: String
  let label: String
  let detail: String
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundColor(.orange)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text(label)
            .font(.body.weight(.medium))
          Text(detail)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        Text("Grant")
          .font(.caption.weight(.medium))
          .foregroundColor(.orange)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isHovering ? Color.orange.opacity(0.08) : Color.orange.opacity(0.04))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(label) permission")
    .accessibilityHint(detail)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
  }
}
