import 'app_settings.dart';

/// Everything that is not a secret, as one JSON blob. One read, one write.
abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
