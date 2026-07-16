import SwiftUI

struct PermissionsBanner: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    VStack(spacing: 4) {
      if !viewModel.snapshot.accessibilityGranted {
        PermissionRow(
          icon: "keyboard",
          label: "Accessibility",
          detail: "Lets ParaDict detect your shortcut anywhere",
          actionTitle: "Open Settings"
        ) {
          viewModel.openAccessibilitySettings()
        }
      }

      if !viewModel.snapshot.microphoneGranted {
        PermissionRow(
          icon: "mic.slash",
          label: "Microphone",
          detail: "Lets ParaDict transcribe speech locally",
          actionTitle: "Allow"
        ) {
          Task { await viewModel.requestMicrophone() }
        }
      }
    }
  }
}

private struct PermissionRow: View {
  let icon: String
  let label: String
  let detail: String
  let actionTitle: String
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

        Text(actionTitle)
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
    .accessibilityHint("\(detail). \(actionTitle).")
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
  }
}
