# ParaDict

A macOS menu bar app for fast local transcription via [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Press a hotkey, speak, press again — pasted into the focused window. A cursor-following overlay shows the live preview as you speak. ParaDict was originally based on [MiniWhisper](https://github.com/andyhtran/MiniWhisper).

<video src="https://github.com/user-attachments/assets/d0833c97-f295-4d2e-859c-e4b2886b65e4" width="800"></video>

## Run

ParaDict requires macOS 14 or later, a Swift 6 toolchain, and [just](https://github.com/casey/just).

```bash
just dev
```

This builds, signs, installs ParaDict to `/Applications`, and launches it. On first launch, ParaDict downloads the Parakeet model and requests Microphone and Accessibility permissions. The default recording shortcut is `Option+Shift+R` and can be changed from the menu bar.

If `just dev` fails because the signing identity is missing, open Keychain Access, create a new self-signed certificate, choose `Code Signing`, name it `local-dev`, then rerun `just dev` or set `DEV_CODESIGN_IDENTITY` to a different installed identity.

## License

[MIT](LICENSE)
