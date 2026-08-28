import SwiftUI

struct CleanupSection: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader(title: "Cleanup", icon: "sparkles")

      Toggle(
        isOn: Binding(
          get: { viewModel.snapshot.cleanup.isEnabled },
          set: { enabled in
            viewModel.setCleanupEnabled(enabled)
          }
        )
      ) {
        VStack(alignment: .leading, spacing: 2) {
          Text("S1-mini by Superwhisper")
            .font(.body)
            .foregroundColor(.primary)

          Text(statusText)
            .font(.caption)
            .foregroundColor(statusColor)
        }
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04))
      )
      .accessibilityLabel("Transcript cleanup")
      .accessibilityValue(viewModel.snapshot.cleanup.status.description)
      .accessibilityHint(
        "Clean up transcripts locally with S1-mini by Superwhisper before pasting"
      )
      .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.12)) {
          isHovering = hovering
        }
      }
    }
  }

  private var statusText: String {
    let status = viewModel.snapshot.cleanup.status
    if status.status == .failed {
      return "Load failed — will retry on next enable"
    }
    return status.description
  }

  private var statusColor: Color {
    switch viewModel.snapshot.cleanup.status.status {
    case .off: return .secondary
    case .preparing: return .secondary
    case .ready: return .green
    case .failed: return .orange
    }
  }
}
