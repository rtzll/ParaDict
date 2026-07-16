import Accessibility
import SwiftUI

struct HistoryView: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  let onBack: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button(action: onBack) {
          Image(systemName: "chevron.left")
            .font(.caption.weight(.semibold))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Back to controls")
        .help("Back")

        Text("History")
          .font(.body.weight(.semibold))

        Spacer()

        Button {
          viewModel.openRecordingsFolder()
        } label: {
          Image(systemName: "folder")
            .font(.body)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Recordings Folder")
        .help("Open Recordings Folder")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()
        .padding(.horizontal, 12)

      VStack(alignment: .leading, spacing: 6) {
        Text("Recent Transcripts")
          .font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
          .textCase(.uppercase)
          .tracking(0.5)
          .padding(.horizontal, 10)

        if viewModel.snapshot.recentHistoryItems.isEmpty {
          Text("No recent transcripts")
            .font(.body)
            .foregroundColor(.secondary)
            .italic()
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
        } else {
          VStack(spacing: 2) {
            ForEach(viewModel.snapshot.recentHistoryItems) { recording in
              HistoryRow(recording: recording)
            }
          }
        }
      }
      .padding(12)
    }
    .frame(width: 340)
  }
}

private struct HistoryRow: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  let recording: Recording
  @State private var copied = false
  @State private var isHovering = false

  var body: some View {
    Group {
      if let text = recording.transcription?.text {
        Button {
          viewModel.copyRecordingText(text)
          copied = true
          AccessibilityNotification.Announcement("Transcript copied").post()
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
          }
        } label: {
          rowContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryText)
        .accessibilityValue(copied ? "Copied" : formatDate(recording.createdAt))
        .accessibilityHint("Copy transcript")
      } else {
        rowContent
      }
    }
    .animation(.easeInOut(duration: 0.12), value: isHovering)
    .animation(
      accessibilityReduceMotion
        ? .easeOut(duration: 0.15)
        : .spring(response: 0.25, dampingFraction: 0.85),
      value: copied
    )
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
  }

  private var rowContent: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Text(primaryText)
          .font(.body)
          .lineLimit(2)
          .foregroundColor(recording.transcription != nil ? .primary : .secondary)

        HStack(spacing: 4) {
          Text(formatDate(recording.createdAt))
            .font(.caption)
            .foregroundColor(.secondary)

          if recording.transcription != nil {
            Text("·")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(recording.configuration.voiceModel)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer(minLength: 12)

      if recording.transcription != nil {
        if copied {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.system(size: 15))
            .transition(
              accessibilityReduceMotion ? .opacity : .scale.combined(with: .opacity)
            )
            .accessibilityHidden(true)
        } else if isHovering {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .transition(
              accessibilityReduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.8))
            )
            .accessibilityHidden(true)
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
    )
    .contentShape(Rectangle())
  }

  private var primaryText: String {
    if let text = recording.transcription?.text {
      return text
    }
    return "No transcription"
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}
