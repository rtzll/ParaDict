import SwiftUI

struct RecordingHeaderView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: statusIcon)
        .font(.system(size: 13))
        .foregroundColor(statusColor)
        .frame(width: 20)
        .animation(.easeInOut(duration: 0.15), value: statusIcon)

      Text(statusText)
        .font(.system(size: 13, weight: .medium))

      Spacer()

      if viewModel.recordingState.isRecording {
        Text(formatDuration(viewModel.currentDuration))
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
      } else if !viewModel.isModelLoaded {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var statusIcon: String {
    if !viewModel.allPermissionsGranted {
      return "exclamationmark.triangle.fill"
    }
    switch viewModel.recordingState {
    case .idle: return "waveform"
    case .recording: return "record.circle.fill"
    case .processing: return "waveform.badge.ellipsis"
    case .error: return "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    if !viewModel.allPermissionsGranted {
      return .orange
    }
    switch viewModel.recordingState {
    case .idle: return .secondary
    case .recording: return .red
    case .processing: return .orange
    case .error: return .red
    }
  }

  private var statusText: String {
    if !viewModel.allPermissionsGranted {
      return "Permissions Required"
    }
    switch viewModel.recordingState {
    case .idle:
      return viewModel.isModelLoaded ? "Ready" : "Loading Parakeet..."
    case .recording: return "Recording"
    case .processing: return "Transcribing..."
    case .error(let msg): return msg
    }
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
