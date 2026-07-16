import SwiftUI

struct MenuBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @State private var page: Page = .controls

  var body: some View {
    Group {
      switch page {
      case .controls:
        controls
      case .history:
        HistoryView {
          page = .controls
        }
      }
    }
    .frame(width: 340)
    .environment(viewModel)
    .onDisappear {
      page = .controls
    }
  }

  private var controls: some View {
    VStack(spacing: 0) {
      RecordingHeaderView()
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

      Divider()
        .padding(.horizontal, 12)

      if !viewModel.snapshot.allPermissionsGranted {
        PermissionsBanner()
          .padding(.horizontal, 16)
          .padding(.top, 14)
      }

      VStack(spacing: 20) {
        MicrophoneSection()
        ShortcutSection()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      if viewModel.snapshot.allPermissionsGranted {
        Divider()
          .padding(.horizontal, 12)

        StatsBarView()
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
      }

      Divider()
        .padding(.horizontal, 12)

      FooterBarView {
        page = .history
      }
    }
  }

  private enum Page {
    case controls
    case history
  }
}
