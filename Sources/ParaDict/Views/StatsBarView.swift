import SwiftUI

struct StatsBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    HStack(spacing: 10) {
      StatSummary(label: "Recordings", value: viewModel.snapshot.statistics.formattedRecordings)

      Divider()
        .frame(height: 24)

      StatSummary(label: "Speaking", value: viewModel.snapshot.statistics.formattedSpeakingTime)

      Divider()
        .frame(height: 24)

      StatSummary(label: "Words", value: viewModel.snapshot.statistics.formattedWords)
    }
    .help("Average \(viewModel.snapshot.statistics.averageWPM) words per minute")
  }
}

private struct StatSummary: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 2) {
      Text(label)
        .font(.caption.weight(.medium))
        .foregroundColor(.secondary)

      Text(value)
        .font(.system(.callout, design: .rounded, weight: .semibold))
        .foregroundColor(.primary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(value)
  }
}
