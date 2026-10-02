import 'dart:convert';
import 'dart:io';

/// HTTP-переопределения, которые резолвят DNS через DoH (DNS-over-HTTPS).
///
/// Зачем: провайдеры в РФ блокируют/замедляют DNS-ответы для некоторых
/// доменов (например *.supabase.co). Системный DNS возвращает NXDOMAIN
/// или таймаут, и картинки/данные не грузятся. DoH-сервер (Comss)
/// не фильтрует эти домены и возвращает правильный IP.
///
/// Как работает:
///   1. При создании резолвим IP DoH-сервера через системный DNS
///   2. В connectionFactory: резолвим hostname → IP через DoH
///   3. TCP-подключение по IP (RawSocket.connect)
///   4. TLS поверх с правильным SNI (RawSecureSocket.secure(host: hostname))
///   5. Возвращаем ConnectionTask.fromSocket
///
/// Шаг 4 критичен: без явного host в secure() SNI был бы IP-адресом,
/// и Cloudflare отвергал бы TLS handshake.
class DohHttpOverrides extends HttpOverrides {
  static const _dohHost = 'dns.comss.one';
  static const _dohPath = '/dns-query';

  final String _dohIp;
  final Map<String, String> _cache = {};

  DohHttpOverrides._(this._dohIp);

  /// Создаёт overrides. Резолвит IP DoH-сервера через системный DNS.
  /// Возвращает null если dns.comss.one недоступен.
  static Future<DohHttpOverrides?> create() async {
    try {
      final addresses = await InternetAddress.lookup(_dohHost)
          .timeout(const Duration(seconds: 5));
      final ipv4 =
          addresses.where((a) => a.type == InternetAddressType.IPv4).firstOrNull;
      if (ipv4 == null) return null;
      return DohHttpOverrides._(ipv4.address);
    } catch (_) {
      return null;
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = _connectionFactory;
    return client;
  }

  Future<ConnectionTask<Socket>> _connectionFactory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = url.host;
    final port = url.port;
    final isSecure = url.scheme == 'https';

    // IP-адреса и сам DoH-сервер не резолвим через DoH.
    if (InternetAddress.tryParse(host) != null || host == _dohHost) {
      if (isSecure) {
        return _secureConnectTask(host, port, host);
      }
      return Socket.startConnect(host, port);
    }

    // DoH-резолвинг с кэшем.
    String? ip;
    try {
      ip = _cache[host] ?? await _resolveViaDoh(host);
      if (ip != null) _cache[host] = ip;
    } catch (_) {}

    if (ip != null && isSecure) {
      // TCP по IP + TLS с SNI = оригинальный hostname.
      return _secureConnectTask(ip, port, host);
    }

    if (ip != null) {
      return Socket.startConnect(ip, port);
    }

    // Fallback: системный DNS.
    if (isSecure) {
      return SecureSocket.startConnect(host, port);
    }
    return Socket.startConnect(host, port);
  }

  /// TCP по [target] (IP или hostname), затем TLS с SNI = [sniHost].
  Future<ConnectionTask<Socket>> _secureConnectTask(
    String target,
    int port,
    String sniHost,
  ) async {
    // 1. Raw TCP по IP (без TLS).
    final rawSocket = await RawSocket.connect(target, port,
        timeout: const Duration(seconds: 10));

    // 2. TLS поверх raw socket с явным SNI.
    final secureSocket = await RawSecureSocket.secure(
      rawSocket,
      host: sniHost,
    );

    // 3. Оборачиваем в ConnectionTask.
    return ConnectionTask.fromSocket(
      Future.value(secureSocket as Socket),
      () => secureSocket.close(),
    );
  }

  /// DoH JSON API запрос через SecureSocket напрямую по IP DoH-сервера.
  Future<String?> _resolveViaDoh(String hostname) async {
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

      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));

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
