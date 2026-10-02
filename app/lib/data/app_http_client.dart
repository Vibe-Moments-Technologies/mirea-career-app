import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Глобальный HTTP-клиент с поддержкой DoH (DNS-over-HTTPS).
///
/// Единая точка для всех сетевых запросов приложения.
/// По умолчанию DoH включён (Comss DNS). Выключение через [useSystemDns]
/// переключает на системный DNS без перезапуска.
///
/// НЕ использует HttpOverrides.createHttpClient — тот вызывается Flutter'ом
/// рекурсивно при TLS-handshake и вызывает StackOverflow. Вместо этого:
/// - Один глобальный [_client] с connectionFactory
/// - DohNetworkImage использует fetchBytes() через этот клиент
/// - Supabase получает этот клиент через custom HttpClientAdapter
class AppHttpClient {
  AppHttpClient._();

  static final AppHttpClient instance = AppHttpClient._();

  static const _dohHost = 'dns.comss.one';
  static const _dohPath = '/dns-query';

  String? _dohIp;
  final Map<String, String> _cache = {};
  bool _systemDns = false;

  /// Глобальный HttpClient с DoH connectionFactory.
  /// Создаётся один раз, переиспользуется везде.
  late final HttpClient _client;

  /// Инициализация. Вызывается один раз при старте.
  Future<void> init({bool systemDns = false}) async {
    _systemDns = systemDns;
    if (!systemDns) {
      try {
        final addresses = await InternetAddress.lookup(_dohHost)
            .timeout(const Duration(seconds: 5));
        final ipv4 = addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .firstOrNull;
        _dohIp = ipv4?.address;
      } catch (_) {
        _dohIp = null;
      }
    }

    // Создаём ОДИН клиент с connectionFactory.
    _client = HttpClient();
    _client.connectionFactory = _connectionFactory;

    // HttpOverrides для Supabase и других библиотек, которые создают
    // свои HttpClient. Переопределяем createHttpClient, но вызываем
    // super.createHttpClient (не new HttpClient()) чтобы избежать рекурсии.
    HttpOverrides.global = _DohOverrides(this);
  }

  void setSystemDns(bool value) {
    _systemDns = value;
    if (value) {
      _dohIp = null;
      _cache.clear();
    } else if (_dohIp == null) {
      _initDohAsync();
    }
  }

  bool get isSystemDns => _systemDns || _dohIp == null;

  /// Возвращает глобальный HttpClient для использования в Supabase adapter.
  HttpClient get httpClient => _client;

  Future<void> _initDohAsync() async {
    try {
      final addresses = await InternetAddress.lookup(_dohHost)
          .timeout(const Duration(seconds: 5));
      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      _dohIp = ipv4?.address;
    } catch (_) {}
  }

  /// Загружает байты по URL через глобальный DoH-клиент.
  Future<Uint8List?> fetchBytes(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final request = await _client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    }
  }

  Future<ConnectionTask<Socket>> _connectionFactory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = url.host;
    final port = url.port;
    final isSecure = url.scheme == 'https';

    // Системный DNS или IP-адрес — обычное подключение.
    if (_systemDns || _dohIp == null) {
      return isSecure
          ? SecureSocket.startConnect(host, port)
          : Socket.startConnect(host, port);
    }

    // Сам DoH-сервер и IP-адреса не резолвим через DoH.
    if (InternetAddress.tryParse(host) != null || host == _dohHost) {
      return isSecure
          ? SecureSocket.startConnect(host, port)
          : Socket.startConnect(host, port);
    }

    // DoH-резолвинг с кэшем.
    String? ip;
    try {
      ip = _cache[host] ?? await _resolveViaDoh(host);
      if (ip != null) _cache[host] = ip;
    } catch (_) {}

    if (ip != null && isSecure) {
      return _secureConnectTask(ip, port, host);
    }
    if (ip != null) {
      return Socket.startConnect(ip, port);
    }

    // Fallback: системный DNS.
    return isSecure
        ? SecureSocket.startConnect(host, port)
        : Socket.startConnect(host, port);
  }

  /// TCP по IP + TLS с правильным SNI.
  Future<ConnectionTask<Socket>> _secureConnectTask(
    String target,
    int port,
    String sniHost,
  ) async {
    final rawSocket = await RawSocket.connect(target, port,
        timeout: const Duration(seconds: 10));
    final secureSocket = await RawSecureSocket.secure(
      rawSocket,
      host: sniHost,
    );
    return ConnectionTask.fromSocket(
      Future.value(secureSocket as Socket),
      () => secureSocket.close(),
    );
  }

  /// DoH JSON API через SecureSocket напрямую по IP (без HttpClient).
  Future<String?> _resolveViaDoh(String hostname) async {
    final dohIp = _dohIp;
    if (dohIp == null) return null;

    final socket = await SecureSocket.connect(
      dohIp,
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

/// Виджет загрузки картинки через глобальный AppHttpClient.
class DohNetworkImage extends StatefulWidget {
  const DohNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<DohNetworkImage> createState() => _DohNetworkImageState();
}

class _DohNetworkImageState extends State<DohNetworkImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DohNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
      _bytes = null;
    });

    final bytes = await AppHttpClient.instance.fetchBytes(widget.url);
    if (!mounted) return;

    if (bytes != null) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } else {
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.placeholder ?? const SizedBox.shrink();
    if (_error || _bytes == null) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
    );
  }
}

/// HttpOverrides для библиотек (Supabase), которые создают свои HttpClient.
///
/// ВАЖНО: createHttpClient вызывает super.createHttpClient(), а НЕ
/// HttpClient(). Это критично: new HttpClient() снова триггерит overrides
/// → бесконечная рекурсия → StackOverflow. super.createHttpClient() создаёт
/// базовый клиент без overrides, на который мы безопасно ставим connectionFactory.
class _DohOverrides extends HttpOverrides {
  final AppHttpClient _app;
  _DohOverrides(this._app);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // super.createHttpClient — базовый клиент БЕЗ overrides.
    // НЕ использовать HttpClient() — это вызовет рекурсию.
    final client = super.createHttpClient(context);
    client.connectionFactory = _app._connectionFactory;
    return client;
  }
}
