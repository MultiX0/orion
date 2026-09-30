/// A value or a typed failure. Async work that can fail returns this
/// instead of throwing.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  /// Unwraps for callers that live inside a Riverpod async provider,
  /// where a thrown Failure becomes an AsyncError.
  T getOrThrow() => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) => switch (this) {
    Ok(:final value) => ok(value),
    Err(:final failure) => err(failure),
  };

  Result<U> map<U>(U Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

/// The small family of things that can go wrong. Every layer maps its own
/// errors onto one of these so screens can show the right copy.
sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Could not reach the host, or it answered with an unexpected status.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {this.statusCode});
  final int? statusCode;
}

/// The pairing token is missing or the board rejected it (401).
final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Not paired, or the token was rejected']);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// The board answered with its own { error, message } shape.
final class DeviceFailure extends Failure {
  const DeviceFailure(this.code, super.message);
  final String code;
}

enum ProviderFailureKind { badKey, badModel, network }

/// An LLM or Fish Audio call failed. kind tells the UI what to suggest.
final class ProviderFailure extends Failure {
  const ProviderFailure(this.kind, super.message, {this.statusCode});
  final ProviderFailureKind kind;
  final int? statusCode;
}

final class ParseFailure extends Failure {
  const ParseFailure(super.message);
}

final class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure(super.message);
}

/// What went wrong talking to a board over Bluetooth, so the setup screens
/// can say what to do next.
enum BluetoothProblem {
  /// The radio is off.
  off,

  /// The user said no to the permission prompt.
  denied,

  /// This device or this build has no Bluetooth LE.
  unsupported,

  /// The board went out of range or dropped the link.
  lostBoard,

  /// The six digit code did not match the one on the board's screen.
  wrongCode,

  /// The board answered but not the way the protocol says.
  protocol,
}

final class BluetoothFailure extends Failure {
  const BluetoothFailure(this.problem, super.message);
  final BluetoothProblem problem;
}

/// The feature does not exist on this platform, for example the harness on a phone.
final class UnsupportedFailure extends Failure {
  const UnsupportedFailure(super.message);
}
