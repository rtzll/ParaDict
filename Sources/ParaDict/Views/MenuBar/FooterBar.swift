import SwiftUI

struct FooterBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @State private var showHistory = false

  var body: some View {
    HStack(spacing: 0) {
      Spacer()

      FooterButton(icon: "folder.fill", label: "Files", color: .secondary) {
        viewModel.openRecordingsFolder()
      }

      FooterButton(icon: "clock.arrow.circlepath", label: "History", color: .secondary) {
        showHistory.toggle()
      }
      .popover(isPresented: $showHistory, arrowEdge: .bottom) {
        HistoryPopoverView()
      }

      FooterButton(icon: "xmark.circle", label: "Quit", color: .red) {
        viewModel.quitApplication()
      }

      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
  }
}

private struct FooterButton: View {
  let icon: String
  let label: String
  var color: Color = .secondary
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .font(.system(size: 13))
          .foregroundColor(color)
          .frame(width: 24, height: 20)

        Text(label)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
  }
}
