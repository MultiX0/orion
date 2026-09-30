import '../../features/device/domain/device.dart';
import 'app_settings.dart';
import 'settings_store.dart';

/// In-memory fake. Starts already paired so the app lands on Home.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([AppSettings? initial])
    : _settings = initial ?? const AppSettings();

  factory InMemorySettingsStore.paired() => InMemorySettingsStore(
    const AppSettings(
      pairedDevice: Device(
        id: 'orion-mock',
        name: 'Orion',
        host: 'localhost:8080',
        fwVersion: '0.1.0-mock',
      ),
    ),
  );

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}
