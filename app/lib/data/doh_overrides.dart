import 'dart:convert';
import 'dart:io';

/// HTTP-переопределения, которые резолвят DNS через DoH (DNS-over-HTTPS).
///
/// Зачем: провайдеры в РФ блокируют/замедляют DNS-ответы для некоторых
/// доменов (например *.supabase.co). Системный DNS возвращает NXDOMAIN
/// или таймаут, и картинки/данные не грузятся. DoH-сервер (Comss)
/// не фильтрует эти домены и возвращает правильный IP.
///
/// Как работает: переопределяем `connectionFactory` в `HttpOverrides`,
/// чтобы перед подключением резолвить hostname через HTTPS-запрос к
/// DoH-серверу вместо системного DNS.
///
/// ВАЖНО: DoH-запрос сам идёт через системный DNS (не через себя).
/// Для этого мы один раз резолвим IP DoH-сервера при создании overrides
/// и потом подключаемся к нему напрямую по IP, минуя connectionFactory.
class DohHttpOverrides extends HttpOverrides {
  /// URL DoH-сервера (JSON API).
  static const _dohHost = 'dns.comss.one';
  static const _dohPath = '/dns-query';

  /// Заранее зарезолвленный IP DoH-сервера.
  /// Резолвим один раз при создании через системный DNS (до установки
  /// overrides), чтобы избежать рекурсии: DoH-запрос → DoH-резолвинг → ∞.
  final String _dohIp;

  DohHttpOverrides._(this._dohIp);

  /// Создаёт overrides с предварительно зарезолвленным IP DoH-сервера.
  ///
  /// Вызывается ДО установки HttpOverrides.global, поэтому резолвинг
  /// идёт через системный DNS. Если dns.comss.one заблокирован и на
  /// уровне DNS — вернёт null, и DoH включать нельзя.
  static Future<DohHttpOverrides?> create() async {
    try {
      final addresses = await InternetAddress.lookup(_dohHost)
          .timeout(const Duration(seconds: 5));
      final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4).firstOrNull;
      if (ipv4 == null) return null;
      return DohHttpOverrides._(ipv4.address);
    } catch (_) {
      return null;
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
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

    // IP-адреса и сам DoH-сервер не нужно резолвить через DoH.
    if (InternetAddress.tryParse(host) != null || host == _dohHost) {
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

  /// Запрашивает A-запись через DoH JSON API, подключаясь по IP.
  ///
  /// Использует RawSocket + ручной HTTP/1.1 запрос, чтобы полностью
  /// обойти HttpOverrides и избежать рекурсии. TLS через SecureSocket.
  Future<String?> _resolveViaDoh(String hostname) async {
    // Подключаемся напрямую по IP DoH-сервера, минуя connectionFactory.
    final socket = await SecureSocket.connect(
      _dohIp,
      443,
      timeout: const Duration(seconds: 5),
    );

    try {
      final path = '$_dohPath?name=$hostname&type=A';
      final request = 'GET $path HTTP/1.1\r\n'
          'Host: $_dohHost\r\n'
          'Accept: application/dns-json\r\n'
          'Connection: close\r\n'
          '\r\n';
      socket.add(utf8.encode(request));
      await socket.flush();

      final response = await utf8.decoder.bind(socket).join().timeout(
            const Duration(seconds: 5),
          );

      // Парсим HTTP-ответ: отделяем заголовки от тела.
      final headerEnd = response.indexOf('\r\n\r\n');
      if (headerEnd < 0) return null;

      final statusLine = response.substring(0, response.indexOf('\r\n'));
      if (!statusLine.contains('200')) return null;

      final body = response.substring(headerEnd + 4);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final answers = json['Answer'] as List<dynamic>?;
      if (answers == null || answers.isEmpty) return null;

      for (final a in answers) {
        if (a is Map<String, dynamic> && a['type'] == 1) {
          return a['data'] as String?;
        }
      }
      return null;
    } finally {
      socket.destroy();
    }
  }
}
