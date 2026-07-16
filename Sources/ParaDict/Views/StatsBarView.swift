import SwiftUI

struct StatsBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    HStack(spacing: 6) {
      StatCard(label: "Recordings", value: viewModel.snapshot.statistics.formattedRecordings)
      StatCard(label: "Duration", value: viewModel.snapshot.statistics.formattedSpeakingTime)
      StatCard(label: "Words", value: viewModel.snapshot.statistics.formattedWords)
      StatCard(label: "Avg WPM", value: "\(viewModel.snapshot.statistics.averageWPM)")
    }
  }
}

private struct StatCard: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.caption.weight(.medium))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .tracking(0.3)

      Text(value)
        .font(.system(.headline, design: .rounded, weight: .semibold))
        .foregroundColor(.primary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.08))
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(value)
  }
}
