import SwiftUI

struct RecordingOverlayView: View {
  let state: RecordingState
  let duration: TimeInterval
  let meterLevel: Double
  let partialTranscript: String
  let overlayStatus: OverlayStatus?
  let overlayHint: OverlayHint?

  static let compactSize = CGSize(width: 210, height: 64)
  static let expandedSize = CGSize(width: 340, height: 124)
  /// Wide-but-short layout for status messages (e.g. cancellation toast).
  /// Matches the recording panel's width so the transition is a vertical
  /// collapse rather than a shrink.
  static let statusSize = CGSize(width: 340, height: 64)

  private let cornerRadius: CGFloat = 20

  var body: some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(width: width, height: height)
      .background(
        overlayShape
          .fill(.regularMaterial)
          .overlay(
            overlayShape
              .fill(Color.black.opacity(0.35))
          )
      )
      .overlay(
        overlayShape
          .strokeBorder(borderColor, lineWidth: 1)
      )
      .overlay(alignment: .bottom) {
        if let overlayHint, overlayStatus == nil {
          overlayHintView(message: overlayHint.message)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
      }
      .clipShape(overlayShape)
      .colorScheme(.dark)
  }

  @ViewBuilder
  private var content: some View {
    if usesExpandedLayout {
      transcriptFocusedLayout
    } else {
      compactLayout
    }
  }

  private var compactLayout: some View {
    HStack(spacing: 12) {
      statusBadge

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)

        HStack(spacing: 8) {
          Text(subtitle)
            .font(.system(size: 11, weight: .medium, design: subtitleFontDesign))
            .foregroundStyle(.secondary)
            .lineLimit(2)

          if case .recording = state {
            OverlayMeterView(level: meterLevel)
          }
        }
      }

      Spacer(minLength: 0)
    }
  }

  private var transcriptFocusedLayout: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 8) {
        headerStatusBadge

        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)

        Spacer(minLength: 8)

        headerTrailingContent
      }

      transcriptSection
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch state {
    case .idle:
      if let overlayStatus {
        statusBadge(for: overlayStatus.kind, size: 32)
      } else {
        EmptyView()
      }
    case .recording:
      statusBadge(for: .error, isRecording: true, size: 32)
    case .processing:
      processingBadge(size: 32)
    case .error:
      statusBadge(for: .error, size: 32)
    }
  }

  @ViewBuilder
  private var headerStatusBadge: some View {
    switch state {
    case .idle:
      if let overlayStatus {
        statusBadge(for: overlayStatus.kind, size: 20)
      }
    case .recording:
      statusBadge(for: .error, isRecording: true, size: 20)
    case .processing:
      processingBadge(size: 20)
    case .error:
      statusBadge(for: .error, size: 20)
    }
  }

  private var title: String {
    if let overlayStatus {
      return overlayStatus.title
    }
    switch state {
    case .recording:
      return "Recording"
    case .processing:
      return "Transcribing"
    case .error(let message):
      return message.isEmpty ? "Error" : "Error"
    case .idle:
      return ""
    }
  }

  private var subtitle: String {
    if let overlayStatus {
      return overlayStatus.message ?? ""
    }
    switch state {
    case .recording:
      return Self.formatDuration(duration)
    case .processing:
      return "Parakeet"
    case .error(let message):
      return message
    case .idle:
      return ""
    }
  }

  /// Free-form status/error copy reads better in the default design; the
  /// monospaced variant is only useful for duration-style subtitles.
  private var subtitleFontDesign: Font.Design {
    overlayStatus == nil ? .monospaced : .default
  }

  private var usesExpandedLayout: Bool {
    guard overlayStatus == nil else { return false }

    switch state {
    case .recording, .processing:
      return true
    case .idle, .error:
      return hasTranscript
    }
  }

  private var hasTranscript: Bool {
    !displayTranscript.isEmpty
  }

  private var width: CGFloat {
    if usesExpandedLayout { return Self.expandedSize.width }
    if overlayStatus != nil { return Self.statusSize.width }
    return Self.compactSize.width
  }

  private var height: CGFloat {
    if usesExpandedLayout { return Self.expandedSize.height }
    if overlayStatus != nil { return Self.statusSize.height }
    return Self.compactSize.height
  }

  private var overlayShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  private var transcriptSection: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        Text(transcriptText)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(hasTranscript ? .primary : .secondary)
          .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .id("bottom")
      }
      .frame(height: 56)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.white.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.white.opacity(0.05), lineWidth: 1)
      )
      .onChange(of: displayTranscript) {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
    .transaction { $0.disablesAnimations = true }
  }

  private var transcriptText: String {
    if hasTranscript {
      return displayTranscript
    }

    switch state {
    case .recording:
      return "Listening..."
    case .processing:
      return "Waiting for transcript..."
    case .idle, .error:
      return ""
    }
  }

  private var displayTranscript: String {
    var text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    while text.hasSuffix("...") {
      text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }

  private var borderColor: Color {
    if let overlayStatus {
      switch overlayStatus.kind {
      case .info:
        return .blue.opacity(0.18)
      case .warning:
        return .orange.opacity(0.22)
      case .error:
        return .red.opacity(0.22)
      }
    }
    switch state {
    case .recording:
      return .red.opacity(0.22)
    case .processing:
      return .orange.opacity(0.18)
    case .error:
      return .red.opacity(0.22)
    case .idle:
      return .clear
    }
  }

  private static func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  @ViewBuilder
  private var headerTrailingContent: some View {
    HStack(spacing: 8) {
      switch state {
      case .recording:
        OverlayMeterView(level: meterLevel, barWidth: 3, frameHeight: 12, spacing: 2)

        Text(Self.formatDuration(duration))
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(.primary)
      case .processing:
        Text(subtitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      case .error, .idle:
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func overlayHintView(message: String) -> some View {
    Text(message)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(.white.opacity(0.92))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule(style: .continuous)
          .fill(Color.black.opacity(0.72))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private func statusBadge(
    for kind: OverlayStatusKind,
    isRecording: Bool = false,
    size: CGFloat
  ) -> some View {
    switch (kind, isRecording) {
    case (_, true):
      ZStack {
        Circle()
          .fill(.red.opacity(0.2))
          .frame(width: size, height: size)

        Circle()
          .fill(.red)
          .frame(width: max(8, size * 0.375), height: max(8, size * 0.375))
      }
    case (.warning, _):
      ZStack {
        Circle()
          .fill(.orange.opacity(0.18))
          .frame(width: size, height: size)

        Image(systemName: "xmark")
          .font(.system(size: max(9, size * 0.38), weight: .bold))
          .foregroundStyle(.orange)
      }
    case (.error, _):
      ZStack {
        Circle()
          .fill(.red.opacity(0.18))
          .frame(width: size, height: size)

        Image(systemName: "exclamationmark")
          .font(.system(size: max(10, size * 0.4), weight: .bold))
          .foregroundStyle(.red)
      }
    case (.info, _):
      ZStack {
        Circle()
          .fill(.blue.opacity(0.18))
          .frame(width: size, height: size)

        Image(systemName: "info")
          .font(.system(size: max(9, size * 0.38), weight: .bold))
          .foregroundStyle(.blue)
      }
    }
  }

  private func processingBadge(size: CGFloat) -> some View {
    ZStack {
      Circle()
        .fill(.orange.opacity(0.18))
        .frame(width: size, height: size)

      ProgressView()
        .scaleEffect(size < 24 ? 0.7 : 0.85)
        .tint(.orange)
    }
  }
}

private struct OverlayMeterView: View {
  let level: Double
  var barWidth: CGFloat = 4
  var frameHeight: CGFloat = 16
  var spacing: CGFloat = 3

  var body: some View {
    HStack(alignment: .bottom, spacing: spacing) {
      ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
        Capsule(style: .continuous)
          .fill(.red.gradient)
          .frame(width: barWidth, height: height)
      }
    }
    .frame(height: frameHeight)
  }

  private var barHeights: [CGFloat] {
    let normalized = max(0.18, min(level, 1))
    let shortBar = frameHeight * 0.35
    let midBar = frameHeight * 0.48
    let tallGain = frameHeight * 0.42
    let midGain = frameHeight * 0.36

    return [
      shortBar + normalized * midGain,
      midBar + normalized * tallGain,
      shortBar + normalized * midGain,
    ]
  }
}
