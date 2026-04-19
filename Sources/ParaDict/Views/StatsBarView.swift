import SwiftUI

struct StatsBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    HStack(spacing: 6) {
      StatCard(label: "Recordings", value: viewModel.formattedRecordings)
      StatCard(label: "Duration", value: viewModel.formattedSpeakingTime)
      StatCard(label: "Words", value: viewModel.formattedWords)
      StatCard(label: "Avg WPM", value: viewModel.averageWPM)
    }
  }
}

private struct StatCard: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .tracking(0.3)

      Text(value)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundColor(.primary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.08))
    )
  }
}
