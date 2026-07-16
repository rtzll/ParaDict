# ParaDict

A [MiniWhisper](https://github.com/andyhtran/MiniWhisper) fork.

macOS menu bar app for fast local transcription via [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Press a hotkey, speak, press again - pasted into the focused window. A cursor-following overlay shows the live preview as you speak.

<video src="https://github.com/user-attachments/assets/a41121f2-6115-46bc-bc66-da5715d83f07" width="800"></video>

## Run

```bash
just dev
```

If `just dev` fails because the signing identity is missing, open Keychain Access, create a new self-signed certificate, choose `Code Signing`, name it `local-dev`, then rerun `just dev` or set `DEV_CODESIGN_IDENTITY` to a different installed identity.

## License

[MIT](LICENSE)
