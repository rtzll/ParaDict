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

      if viewModel.snapshot.recordingState.isRecording {
        Text(formatDuration(viewModel.snapshot.currentDuration))
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
      } else if viewModel.snapshot.allPermissionsGranted,
        viewModel.snapshot.modelReadiness.showsProgress
      {
        ProgressView()
          .controlSize(.small)
      } else if viewModel.snapshot.allPermissionsGranted,
        let retryTitle = viewModel.snapshot.modelReadiness.retryTitle
      {
        Button(retryTitle) {
          viewModel.retryModelLoading()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
      }
    }
  }

  private var statusIcon: String {
    if !viewModel.snapshot.allPermissionsGranted {
      return "exclamationmark.triangle.fill"
    }
    switch viewModel.snapshot.recordingState {
    case .idle: return viewModel.snapshot.modelReadiness.systemImage
    case .recording: return "record.circle.fill"
    case .processing: return "waveform.badge.ellipsis"
    case .error: return "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    if !viewModel.snapshot.allPermissionsGranted {
      return .orange
    }
    switch viewModel.snapshot.recordingState {
    case .idle: return modelReadinessColor
    case .recording: return .red
    case .processing: return .orange
    case .error: return .red
    }
  }

  private var statusText: String {
    if !viewModel.snapshot.allPermissionsGranted {
      return "Permissions Required"
    }
    switch viewModel.snapshot.recordingState {
    case .idle: return viewModel.snapshot.modelReadiness.title
    case .recording: return "Recording"
    case .processing: return "Transcribing..."
    case .error(let msg): return msg
    }
  }

  private var modelReadinessColor: Color {
    switch viewModel.snapshot.modelReadiness.tone {
    case .ready: return .secondary
    case .pending: return .orange
    case .failed: return .red
    }
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
