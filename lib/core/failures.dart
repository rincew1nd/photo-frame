enum FailureKind {
  network,
  auth,
  permission,
  server,
  notFound,
  invalidResponse,
  storage,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.message, {
    this.statusCode,
    this.cause,
  });

  final FailureKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'AppFailure[${kind.name}]$status: $message';
  }
}
