import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// The OS keychain. On a Linux box without libsecret the plugin throws, and
/// a demo that cannot store a key is still better than one that will not
/// start, so this falls back to memory for the session.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _fallback = <String, String>{};
  var _keychainWorks = true;

  @override
  Future<String?> read(String key) async {
    if (!_keychainWorks) return _fallback[key];
    try {
      return await _storage.read(key: key);
    } on Object {
      _keychainWorks = false;
      return _fallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _fallback[key] = value;
    if (!_keychainWorks) return;
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      _keychainWorks = false;
    }
  }

  @override
  Future<void> delete(String key) async {
    _fallback.remove(key);
    if (!_keychainWorks) return;
    try {
      await _storage.delete(key: key);
    } on Object {
      _keychainWorks = false;
    }
  }
}
