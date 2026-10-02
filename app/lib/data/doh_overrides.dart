import 'dart:convert';
import 'dart:io';

/// HTTP-переопределения, которые резолвят DNS через DoH (DNS-over-HTTPS).
///
/// Зачем: провайдеры в РФ блокируют/замедляют DNS-ответы для некоторых
/// доменов (например *.supabase.co). Системный DNS возвращает NXDOMAIN
/// или таймаут, и картинки/данные не грузятся. DoH-сервер (Comss)
/// не фильтрует эти домены и возвращает правильный IP.
///
/// Как работает: переопределяем `findProxy` и `createConnection` в
/// `HttpOverrides`, чтобы перед подключением резолвить hostname через
/// HTTPS-запрос к DoH-серверу вместо системного DNS.
///
/// ponytail: используем только dart:io, без сторонних пакетов.
/// DoH-запрос — обычный HTTPS GET с Accept: application/dns-json.
class DohHttpOverrides extends HttpOverrides {
  /// URL DoH-сервера (JSON API, не wire format).
  static const dohUrl = 'https://dns.comss.one/dns-query';

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Подменяем функцию подключения: вместо прямого TCP к hostname
    // сначала резолвим через DoH, потом подключаемся по IP.
    client.connectionFactory = _dohConnectionFactory;
    return client;
  }

  /// Резолвит hostname через DoH и возвращает соединение по IP.
  Future<ConnectionTask<Socket>> _dohConnectionFactory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = url.host;

    // IP-адреса не нужно резолвить.
    if (InternetAddress.tryParse(host) != null) {
      return Socket.startConnect(host, url.port);
    }

    try {
      final ip = await _resolveViaDoh(host);
      if (ip != null) {
        return await Socket.startConnect(ip, url.port);
      }
    } catch (_) {
      // DoH не ответил — fallback на системный DNS.
    }

    // Fallback: обычный системный резолвинг.
    return Socket.startConnect(host, url.port);
  }

  /// Запрашивает A-запись через DoH JSON API.
  ///
  /// Возвращает первый IPv4-адрес или null, если DoH не ответил
  /// или домен не найден. Таймаут 5 секунд — если DoH тормозит,
  /// лучше упасть в fallback, чем висеть.
  static Future<String?> _resolveViaDoh(String hostname) async {
    final client = HttpClient();
    try {
      // DoH-запрос сам должен идти через системный DNS (не через себя),
      // поэтому используем отдельный клиент без overrides.
      final uri = Uri.parse('$dohUrl?name=$hostname&type=A');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 5));
      request.headers.set('Accept', 'application/dns-json');
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != 200) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;
      final answers = json['Answer'] as List<dynamic>?;
      if (answers == null || answers.isEmpty) return null;

      // Ищем первую A-запись (type 1).
      for (final a in answers) {
        if (a is Map<String, dynamic> && a['type'] == 1) {
          return a['data'] as String?;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
