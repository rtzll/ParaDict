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
          Text("Improve Transcripts")
            .font(.body)
            .foregroundColor(.primary)

          Text(statusText)
            .font(.caption)
            .foregroundColor(statusColor)
            .lineLimit(1)
            .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04))
      )
      .animation(.easeInOut(duration: 0.15), value: statusText)
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
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var statusText: String {
    switch viewModel.snapshot.cleanup.status.status {
    case .off:
      return "S1-mini by Superwhisper"
    case .preparing:
      return "Loading S1-mini by Superwhisper…"
    case .ready:
      return "S1-mini by Superwhisper · Ready"
    case .failed:
      return "S1-mini by Superwhisper · Load failed"
    }
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
