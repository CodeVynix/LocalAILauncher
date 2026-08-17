import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final double temperature;
  final bool webServerEnabled;
  final String webServerUrl;

  const SettingsState({
    this.temperature = 0.7,
    this.webServerEnabled = false,
    this.webServerUrl = '',
  });

  SettingsState copyWith({
    double? temperature,
    bool? webServerEnabled,
    String? webServerUrl,
  }) {
    return SettingsState(
      temperature: temperature ?? this.temperature,
      webServerEnabled: webServerEnabled ?? this.webServerEnabled,
      webServerUrl: webServerUrl ?? this.webServerUrl,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  void setTemperature(double value) {
    state = state.copyWith(temperature: value);
  }

  void setWebServerEnabled(bool value) {
    state = state.copyWith(webServerEnabled: value);
  }

  void setWebServerUrl(String url) {
    state = state.copyWith(webServerUrl: url);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
