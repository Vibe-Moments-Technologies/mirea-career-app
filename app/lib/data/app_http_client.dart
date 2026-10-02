import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Глобальный HTTP-клиент с поддержкой DoH (DNS-over-HTTPS).
///
/// Единая точка для всех сетевых запросов приложения. Используется:
/// - Supabase (через custom HttpClientAdapter)
/// - Загрузка картинок (DohNetworkImage)
/// - Любые другие HTTP-запросы
///
/// По умолчанию DoH включён (Comss DNS). Выключение через [useSystemDns]
/// переключает на системный DNS без перезапуска приложения.
class AppHttpClient {
  AppHttpClient._();

  static final AppHttpClient instance = AppHttpClient._();

  /// URL DoH-сервера (JSON API).
  static const _dohHost = 'dns.comss.one';
  static const _dohPath = '/dns-query';

  /// Заранее зарезолвленный IP DoH-сервера (системный DNS, до установки overrides).
  String? _dohIp;

  /// Кэш DoH-резолвинга: hostname → IP.
  final Map<String, String> _cache = {};

  /// Использовать ли системный DNS вместо DoH.
  bool _systemDns = false;

  /// Инициализация: резолвит IP DoH-сервера через системный DNS.
  /// Вызывается один раз при старте приложения, ДО установки HttpOverrides.
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
        // DoH-сервер недоступен через системный DNS — fallback на системный.
        _dohIp = null;
      }
    }

    // Устанавливаем глобальные overrides.
    HttpOverrides.global = _AppHttpOverrides(this);
  }

  /// Переключить режим DNS. Не требует перезапуска.
  void setSystemDns(bool value) {
    _systemDns = value;
    if (value) {
      _dohIp = null;
      _cache.clear();
    } else if (_dohIp == null) {
      // Пытаемся резолвить DoH-сервер заново.
      _initDohAsync();
    }
  }

  bool get isSystemDns => _systemDns || _dohIp == null;

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

  /// Создаёт HttpClient с DoH connectionFactory.
  HttpClient createClient() {
    final client = HttpClient();
    client.connectionFactory = _connectionFactory;
    return client;
  }

  /// Загружает байты по URL через DoH-клиент.
  Future<Uint8List?> fetchBytes(String url, {Duration timeout = const Duration(seconds: 15)}) async {
    final client = createClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    } finally {
      client.close();
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

  /// TCP по [target] (IP), затем TLS с SNI = [sniHost].
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

  /// DoH JSON API запрос через SecureSocket напрямую по IP.
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

/// HttpOverrides, делегирующий connectionFactory в AppHttpClient.
class _AppHttpOverrides extends HttpOverrides {
  final AppHttpClient _appClient;
  _AppHttpOverrides(this._appClient);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _appClient.createClient();
  }
}

/// Виджет загрузки картинки через глобальный AppHttpClient.
///
/// Использует DoH-клиент вместо Image.network, который игнорирует
/// HttpOverrides.global. При ошибке показывает errorWidget.
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
