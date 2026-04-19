import SwiftUI

struct ShortcutSection: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @State private var isEditing = false
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader(title: "Shortcut", icon: "command")

      if isEditing {
        HStack(spacing: 8) {
          ShortcutRecorderView(
            shortcut: Binding(
              get: { viewModel.toggleRecordingShortcut },
              set: { newShortcut in
                viewModel.updateToggleRecordingShortcut(newShortcut)
                isEditing = false
              }
            ))

          Spacer()

          Button {
            isEditing = false
          } label: {
            Text("Cancel")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.08))
        )
      } else {
        Button {
          isEditing = true
        } label: {
          HStack(spacing: 8) {
            Text("Toggle Recording")
              .font(.system(size: 13))

            Spacer(minLength: 12)

            if let shortcut = viewModel.toggleRecordingShortcut {
              Text(shortcut.compactDisplayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            } else {
              Text("Not Set")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
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
        .buttonStyle(.plain)
        .onHover { hovering in
          withAnimation(.easeInOut(duration: 0.12)) {
            isHovering = hovering
          }
        }
      }
    }
  }
}
