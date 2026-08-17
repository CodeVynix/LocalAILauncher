# Local AI Launcher - Architecture

## Overview

Cross-platform Flutter app for running local GGUF AI models on-device via llama.cpp bindings, with an optional local web server for network access.

## Project Structure

```
LocalAILauncher/
├── .github/workflows/       # CI: Android APK build, iOS placeholder
├── app/                     # Flutter project root
│   ├── lib/
│   │   ├── main.dart        # Entry point, Riverpod ProviderScope
│   │   ├── app.dart         # MaterialApp with dark theme
│   │   ├── models/          # Data models
│   │   │   ├── chat_message.dart
│   │   │   ├── model_info.dart
│   │   │   └── device_info.dart
│   │   ├── providers/       # Riverpod state management
│   │   │   ├── settings_provider.dart
│   │   │   ├── chat_provider.dart
│   │   │   └── model_provider.dart
│   │   ├── services/        # Business logic
│   │   │   ├── device_service.dart
│   │   │   ├── download_service.dart
│   │   │   ├── gguf_validator.dart
│   │   │   ├── shelf_server.dart
│   │   │   └── recommended_models.dart
│   │   ├── screens/         # UI screens
│   │   │   ├── home_screen.dart
│   │   │   ├── chat_screen.dart
│   │   │   ├── download_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/         # Reusable widgets
│   │       ├── chat_bubble.dart
│   │       ├── model_card.dart
│   │       └── download_progress.dart
│   ├── android/             # Android-specific config
│   └── ios/                 # iOS-specific config
└── docs/
    └── ARCHITECTURE.md      # This file
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Inference | `fllama` (llama.cpp Dart bindings via FFI) |
| State | `flutter_riverpod` |
| Local HTTP | `shelf` + `shelf_router` |
| Device info | `device_info_plus` |
| File import | `file_picker` |
| Storage | `path_provider` |

## App Tabs

### Chat
- Shows error if no model selected
- Streams tokens from fllama via `fllamaChat()` callback
- Supports cancel mid-generation

### Download
- **Recommended**: Hardware-detects RAM/CPU, shows filtered GGUF models
- **Import Custom**: File picker with GGUF magic-number validation

### Settings
- Temperature slider (0.0–1.5)
- Web server toggle (shelf on port 8080)
- Model management (select/delete)

## Sideloading

### Android
- Debug-signed APK (no keystore setup needed)
- minSdk 24 (Android 7.0) for llama.cpp NDK compatibility
- No Play Store dependencies

### iOS
- No entitlements beyond standard ad-hoc
- No background modes, push notifications, or App Groups
- Compatible with Feather (ArcticSign cert) and LiveContainer
- Build: `flutter build ios --release` → package .ipa

## Desktop Extensibility

Code avoids mobile-only APIs. Desktop targets (Windows/macOS/Linux) can be added by:
1. `flutter create --platforms=windows,macos,linux .`
2. The fllama package already exports platform-specific code for all platforms
3. `path_provider` and `device_info_plus` work cross-platform
4. The shelf server runs on all platforms natively
