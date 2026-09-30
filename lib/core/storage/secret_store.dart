/// Keys and tokens. Backed by the OS keychain in the real app.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The only key names that go into the SecretStore.
abstract final class SecretKeys {
  static const pairingToken = 'pairing_token';
  static const fishApiKey = 'fish_api_key';
  static String providerApiKey(String providerId) => 'provider_key_$providerId';
}
