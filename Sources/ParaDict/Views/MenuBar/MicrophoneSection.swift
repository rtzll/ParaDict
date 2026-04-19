import SwiftUI

struct MicrophoneSection: View {
  @Environment(MenuBarViewModel.self) private var viewModel
  @State private var showPicker = false
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader(title: "Microphone", icon: "mic.fill")

      Button {
        showPicker.toggle()
      } label: {
        HStack(spacing: 8) {
          Text(viewModel.effectiveDeviceName)
            .font(.system(size: 13))
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 12)

          if viewModel.inputMode == .systemDefault {
            Text("System Default")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          } else if !viewModel.isSelectedDeviceAvailable {
            Text("Unavailable")
              .font(.system(size: 10))
              .foregroundColor(.orange)
          }

          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.12)) {
          isHovering = hovering
        }
      }
      .popover(isPresented: $showPicker, arrowEdge: .bottom) {
        MicrophonePickerView()
      }
    }
  }
}

private struct MicrophonePickerView: View {
  @Environment(MenuBarViewModel.self) private var viewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Input Device")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
        .padding(.horizontal, 10)

      VStack(spacing: 2) {
        // System Default option
        MicPickerRow(
          name: "System Default",
          subtitle: viewModel.systemDefaultDeviceName,
          isSelected: viewModel.inputMode == .systemDefault
        ) {
          viewModel.selectSystemDefaultMicrophone()
        }

        if !viewModel.availableDevices.isEmpty {
          Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 2)

          ForEach(viewModel.availableDevices) { device in
            MicPickerRow(
              name: device.name,
              subtitle: nil,
              isSelected: viewModel.inputMode == .specificDevice
                && viewModel.selectedDeviceUID == device.uid
            ) {
              viewModel.selectDevice(device)
            }
          }
        }
      }
    }
    .padding(12)
    .frame(width: 280)
  }
}

private struct MicPickerRow: View {
  let name: String
  let subtitle: String?
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(.system(size: 13))
            .foregroundColor(.primary)

          if let subtitle {
            Text(subtitle)
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.accentColor)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
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
