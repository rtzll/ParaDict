# ParaDict

A macOS menu bar app for fast local transcription via [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Press a hotkey, speak, press again — pasted into the focused window. A cursor-following overlay shows the live preview as you speak. ParaDict was originally based on [MiniWhisper](https://github.com/andyhtran/MiniWhisper).

<video src="https://github.com/user-attachments/assets/b60cf8ef-7ace-4158-8d3c-66ac6920cf18" width="800"></video>

## Run

ParaDict requires macOS 14 or later, a Swift 6 toolchain, and [just](https://github.com/casey/just).

```bash
just dev
```

This builds, signs, installs ParaDict to `/Applications`, and launches it. On first launch, ParaDict downloads the Parakeet model and requests Microphone and Accessibility permissions. The default recording shortcut is `Option+Shift+R` and can be changed from the menu bar.

## Optional transcript cleanup

ParaDict can clean English transcripts locally after transcription using
[S1-mini by Superwhisper](https://huggingface.co/mlx-community/S1-mini-MLX-4bit).
Enable it from the menu bar's Cleanup section. The approximately 331 MB model is downloaded on
first use, runs on-device with MLX, and falls back to the original transcript if it is unavailable.

If `just dev` fails because the signing identity is missing, open Keychain Access, create a new self-signed certificate, choose `Code Signing`, name it `local-dev`, then rerun `just dev` or set `DEV_CODESIGN_IDENTITY` to a different installed identity.

If the build fails with `cannot execute tool 'metal' due to missing Metal Toolchain`, install Xcode's optional Metal toolchain and rerun the build:

```bash
xcodebuild -downloadComponent MetalToolchain
just update
```

## License

[MIT](LICENSE)

See [Third-party notices](THIRD_PARTY_NOTICES.md) for model and dependency attribution.
