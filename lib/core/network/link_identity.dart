import 'dart:io' show Platform;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../platform/platform_info.dart';
import '../storage/storage_providers.dart';
import 'orion_link.dart';

part 'link_identity.g.dart';

/// The app's version as the other nodes see it. Kept by hand with
/// pubspec.yaml; a test checks that the two agree.
const appVersion = '1.1.0';

/// This install's Orion Link id, made on first use and kept in the settings.
@Riverpod(keepAlive: true)
Future<String> linkId(Ref ref) {
  final info = ref.watch(platformInfoProvider);
  return ref
      .read(appSettingsProvider.notifier)
      .linkId(info.isMobile ? OrionLink.kindPhone : OrionLink.kindPc);
}

/// What this app's server answers at /.well-known/orion, given the port it
/// got. Null until the id has been read, which takes a moment at launch.
Map<String, dynamic>? Function(int port) linkIdentityFor(Ref ref) {
  final info = ref.read(platformInfoProvider);
  // Started now, so the id is ready by the time anything asks.
  ref.read(linkIdProvider);
  return (port) {
    final id = ref.read(linkIdProvider).value;
    if (id == null) return null;
    return OrionLink.identity(
      id: id,
      kind: info.isMobile ? OrionLink.kindPhone : OrionLink.kindPc,
      name: _hostName(),
      port: port,
      appVersion: appVersion,
    );
  };
}

String _hostName() {
  try {
    return Platform.localHostname;
  } on Object {
    return 'Orion app';
  }
}
