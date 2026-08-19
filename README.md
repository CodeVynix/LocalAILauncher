# Local AI Launcher

Cross-platform Flutter app for running local GGUF AI models on-device via llama.cpp, with background downloads, hardware-aware model recommendations, and an optional LAN web server.

## Features

- **On-device inference** -- runs GGUF models locally using [fllama](https://github.com/Telosnex/fllama) (llama.cpp Dart bindings via FFI). No cloud, no API keys.
- **Background downloads** -- model downloads survive app backgrounding and swiping via [background_downloader](https://pub.dev/packages/background_downloader) (WorkManager on Android, URLSession on iOS). Supports pause, resume, and cancel.
- **Hardware-aware recommendations** -- detects device RAM (rounded to standard tiers) and filters the model catalog to what your device can actually run, with a Limited / Good / Excellent tier badge.
- **LAN web server** -- optional Shelf-based HTTP server on port 8080 that exposes a 3-tab web UI (Chat, Download, Settings) to other devices on your WiFi network. Resolves and displays the real LAN IP.
- **Download-complete notifications** -- local notifications via [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) fire when a model finishes downloading, on both Android and iOS.
- **Custom model import** -- pick any `.gguf` file from your device; validated by magic-number check before import.
- **Temperature control** -- adjustable 0.0 -- 1.5 slider passed directly to the inference engine.
- **6 recommended models** -- SmolLM2 1.7B, Gemma 2 2B, Phi-3 Mini 3.8B, Qwen 2.5 3B, Llama 3.2 3B, Dolphin 2.6 Mistral 7B, all Q4_K_M quantized from HuggingFace.

## Requirements

| Platform | Minimum | Notes |
|----------|---------|-------|
| Dart SDK | ^3.13.0 | |
| Flutter | 3.47.0+ | stable channel |
| Android | API 24 (7.0) | llama.cpp NDK requirement |
| iOS | 15.0 | |

## Getting Started

```bash
cd app
flutter pub get
flutter run
```

### Building an APK (Android)

```bash
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

The release build is configured with debug signing for sideloading. No keystore setup is needed.

### Building for iOS

```bash
flutter build ios --release
```

No entitlements beyond standard ad-hoc are required. Compatible with sideloading tools like Feather (ArcticSign certificate) and LiveContainer.

## Project Structure

```
LocalAILauncher/
├── .github/workflows/          CI: Android APK build, iOS placeholder
├── app/                        Flutter project root
│   └── lib/
│       ├── main.dart           Entry point, notification init
│       ├── app.dart            MaterialApp with dark theme
│       ├── models/             Data models
│       │   ├── chat_message.dart
│       │   ├── device_info.dart       RAM tiers, hardware assessment
│       │   └── model_info.dart        GGUF model metadata
│       ├── providers/          Riverpod state management
│       │   ├── chat_provider.dart     fllamaChat integration
│       │   ├── model_provider.dart    Downloaded model list
│       │   └── settings_provider.dart Temperature, web server state
│       ├── services/           Business logic
│       │   ├── device_service.dart         Platform RAM detection
│       │   ├── download_service.dart       background_downloader wrapper
│       │   ├── gguf_validator.dart         Magic-number validation
│       │   ├── notification_service.dart   Local notifications
│       │   ├── recommended_models.dart     Curated model catalog
│       │   └── shelf_server.dart           LAN web server + embedded UI
│       ├── screens/            UI screens
│       │   ├── home_screen.dart
│       │   ├── chat_screen.dart
│       │   ├── download_screen.dart
│       │   └── settings_screen.dart
│       └── widgets/            Reusable widgets
│           ├── chat_bubble.dart
│           ├── download_progress.dart
│           └── model_card.dart
├── docs/
│   └── ARCHITECTURE.md        Detailed architecture doc
└── codemagic.yaml             CI config
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full breakdown including tech stack, tab behavior, sideloading notes, and desktop extensibility.

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [fllama](https://github.com/Telosnex/fllama) | On-device GGUF inference via llama.cpp FFI |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | State management |
| [background_downloader](https://pub.dev/packages/background_downloader) | Background-surviving downloads with pause/resume |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Download-complete notifications |
| [shelf](https://pub.dev/packages/shelf) + shelf_router | LAN HTTP server |
| [device_info_plus](https://pub.dev/packages/device_info_plus) | Device RAM detection |
| [network_info_plus](https://pub.dev/packages/network_info_plus) | WiFi IP resolution for LAN URL |
| [file_picker](https://pub.dev/packages/file_picker) | Custom GGUF import |

## Platform-Specific Notes

### Android

- `minSdk 24` -- required by llama.cpp NDK.
- `compileSdk 36` -- needed for `FOREGROUND_SERVICE_DATA_SYNC` (Android 14+).
- Background downloads use WorkManager with a foreground service (`dataSync` type).
- POST_NOTIFICATIONS permission is declared in the manifest and requested at runtime on first download.
- Debug-signed APK -- no keystore needed for sideloading.

### iOS

- No entitlements required beyond standard ad-hoc.
- Background downloads use URLSession (handled automatically by `background_downloader` via `addApplicationDelegate`).
- Notification permissions requested via `flutter_local_notifications` on first download.
- Compatible with Feather and LiveContainer for sideloading.

## License

Private -- not published to pub.dev.
