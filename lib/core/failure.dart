/// Типизированные ошибки доменного слоя.
sealed class Failure {
  const Failure(this.message);

  final String message;
}

/// Ошибка чтения/записи файлов хранилища.
final class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Ошибка разбора markdown/JSON.
final class ParseFailure extends Failure {
  const ParseFailure(super.message);
}
