import SwiftUI

struct MenuBarView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    VStack(spacing: 0) {
      RecordingHeaderView()
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

      Divider()
        .padding(.horizontal, 12)

      if !viewModel.allPermissionsGranted {
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

      Divider()
        .padding(.horizontal, 12)

      StatsBarView()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

      Divider()
        .padding(.horizontal, 12)

      FooterBarView()
    }
    .frame(width: 340)
    .environment(viewModel)
  }
}
