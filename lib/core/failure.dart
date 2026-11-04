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

/// Ошибка обращения к DeepSeek: сеть, ключ, баланс или непроверенный ответ.
final class AiFailure extends Failure {
  const AiFailure(super.message);
}

/// Модель увидела признаки тяжёлого состояния: вместо подсказок — статичный текст.
final class AiConcern extends Failure {
  const AiConcern(super.message);
}
