import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'use_fakes.g.dart';

/// True only while the app runs on in-memory fakes instead of the real board,
/// storage and providers. Off in the app; tests can override it back on.
@Riverpod(keepAlive: true)
bool useFakes(Ref ref) => false;
