part of 'main.dart';

class _AuthException implements Exception {
  const _AuthException(this.details);

  final String details;

  @override
  String toString() => details;
}

String _humanError(Object error) {
  if (error is _AuthException) {
    return 'Сессия сброшена.\n'
        'Этот пользователь вошел на другом устройстве, в web или в админке. '
        'Войдите заново, черновик сохранен.\n'
        'Детали: ${error.details}';
  }

  if (error is SocketException) {
    return 'SocketException\nНет подключения к серверу.\nДетали: ${error.message}';
  }

  if (error is TimeoutException) {
    return 'TimeoutException\nСервер не ответил вовремя.\nДетали: ${error.message ?? error.toString()}';
  }

  if (error is FormatException) {
    return 'FormatException\nНеверный формат данных.\nДетали: ${error.message}';
  }

  return '${error.runtimeType}\n${error.toString()}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatDateOnly(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year}';
}

String _shortExpertName(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return value.trim();
  }

  return '${parts[1]}.${parts.first.characters.first.toUpperCase()}';
}

bool _isToday(_SentInspection item) {
  final now = DateTime.now();
  final sentAt = item.sentAt;
  return sentAt.year == now.year &&
      sentAt.month == now.month &&
      sentAt.day == now.day;
}

String _extensionForPath(String path) {
  final lastSegment = path.split(Platform.pathSeparator).last;
  final dotIndex = lastSegment.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == lastSegment.length - 1) {
    return '.jpg';
  }

  return lastSegment.substring(dotIndex);
}
