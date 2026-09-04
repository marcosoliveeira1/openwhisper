# OpenWhisper

Lightweight, native macOS voice-to-text tray app. Press a global hotkey, speak, and your words are transcribed, copied to the clipboard — and optionally pasted straight into the app you were using.

Built with Swift, AppKit and Apple's Speech framework. Zero third-party dependencies.

![platform](https://img.shields.io/badge/platform-macOS%2015%2B-black)
![swift](https://img.shields.io/badge/swift-6.3-orange)
![license](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Global hotkey** (default `⌘⇧G`) opens a floating centered panel and starts recording instantly
- **Live transcript** with timer while you speak (Portuguese – Brazil)
- **Auto-copy** to clipboard on Finish — or let **auto-paste** deliver the text into the previously focused app (requires Accessibility permission)
- **Cancel** (`Esc`) discards everything — no side effects
- **Tray menu** with transcription history (click to copy), clear history, settings, about, quit
- **Configurable** — hotkey recorder and history limit (1–500) in the settings UI, persisted between launches
- **On-device speech recognition** when the system supports it (falls back to Apple's server-based recognition otherwise)
- **Lightweight** — tray-only app (no Dock icon), native frameworks only, history persisted as JSON

## Requirements

- macOS 15.0 or later
- Apple Silicon Mac
- Swift 6 toolchain (Xcode 16+) to build

## Build & Run

```bash
git clone https://github.com/marcosoliveeira1/openwhisper.git
cd openwhisper
make app
open build/OpenWhisper.app
```

Or iterate in debug mode:

```bash
make run      # build + bundle + launch
make test     # run the test suite (Swift Testing)
```

## Permissions

| Permission | When | Why |
| ---------- | ---- | --- |
| Microphone | First dictation | Capture audio |
| Speech Recognition | First dictation | Transcribe audio |
| Accessibility | First auto-paste | Synthesize `⌘V` into the previously focused app |

Grant permissions in **System Settings → Privacy & Security** if a prompt is dismissed.

## Usage

1. Press `⌘⇧G` anywhere — the panel opens focused, recording
2. Speak in Portuguese
3. `↩` / **Finalizar** (or `⌘⇧G` again) → transcribe + copy (+ auto-paste) + close
4. `Esc` / **Cancelar** → discard
5. Tray menu → history (click to copy), Configurações, Sobre, Sair

Settings let you change the hotkey, the history limit, and toggle auto-paste.

## Project Structure

```
Sources/OpenWhisper/
├── AppDelegate.swift          # Composition root
├── AppModel.swift             # State machine (idle → recording → transcribing)
├── AutoPaste.swift            # CGEvent ⌘V into previously focused app
├── Clipboard.swift            # NSPasteboard abstraction
├── HotKeyController.swift     # Carbon global hotkey, re-registerable
├── TranscriptionStore.swift   # Actor + JSON persistence, configurable cap
├── Speech/                    # DictationService protocol + AppleSpeechService
├── Panel/                     # NSPanel + SwiftUI dictation UI
├── Settings/                  # Settings window, hotkey recorder, UserDefaults
└── StatusBar/                 # Tray menu + pure menu model builder
```

Specs and design docs live in `.specs/`. Tests use [Swift Testing](https://developer.apple.com/xcode/swift-testing/) — run with `swift test`.

## License

[MIT](LICENSE) © Marcos Oliveira
