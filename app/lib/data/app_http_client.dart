import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Глобальный HTTP-клиент: единая точка всех сетевых запросов.
///
/// Прямая сеть (PocketBase на собственном VDS, блокировок нет):
/// никаких DoH-обёрток. Остаются полезные детали прежнего клиента:
/// - один переиспользуемый HttpClient;
/// - кэш картинок в памяти (URL → байты): скролл не перезагружает;
/// - 2 попытки с паузой: мобильная сеть может терять первый пакет.
class AppHttpClient {
  AppHttpClient._();

  static final AppHttpClient instance = AppHttpClient._();

  late final HttpClient _client = _create();

  HttpClient _create() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    return client;
  }

  /// Кэш загруженных картинок: URL → байты.
  /// Избавляет от повторных HTTP-запросов при скролле ListView.
  final Map<String, Uint8List> _imageCache = {};

  /// Загружает байты по URL.
  ///
  /// [userAgent] — внешний API расписания вуза требует нестандартный UA
  /// и отвечает ошибкой на пустой/дефолтный.
  ///
  /// [cache] — кэшировать результат в памяти. Нужен ТОЛЬКО картинкам
  /// (URL картинок стабильны, повторная загрузка — трата трафика при
  /// скролле). API-запросы (лента, витрина, опросы, справочники) НЕ
  /// кэшируются: иначе pull-to-refresh возвращал бы устаревший ответ
  /// до перезапуска приложения — ровно этот баг был в dev.74.
  /// При ошибке делает одну повторную попытку.
  Future<Uint8List?> fetchBytes(
    String url, {
    Duration timeout = const Duration(seconds: 15),
    String? userAgent,
    bool cache = false,
  }) async {
    // Кэш: если уже загружали — возвращаем сразу.
    if (cache) {
      final cached = _imageCache[url];
      if (cached != null) return cached;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request =
            await _client.getUrl(Uri.parse(url)).timeout(timeout);
        if (userAgent != null) {
          request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        }
        final response = await request.close().timeout(timeout);
        if (response.statusCode != 200) continue;
        final chunks = <int>[];
        await for (final chunk in response.timeout(timeout)) {
          chunks.addAll(chunk);
        }
        final bytes = Uint8List.fromList(chunks);
        if (cache) _imageCache[url] = bytes;
        return bytes;
      } catch (_) {
        if (attempt == 0) {
          // Первая попытка не удалась — ждём немного и пробуем снова.
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return null;
  }

  /// POST JSON: отправка данных (ответы анкет, счётчики).
  ///
  /// Возвращает true при 2xx. Не кэшируется — это запись, не чтение.
  /// Повтор при неудаче НЕ делаем: повторная отправка анкеты создала бы
  /// дубль записи; повторение таких операций решает вызывающая сторона.
  ///
  /// [visitorId] — анонимный идентификатор устройства для маршрутов
  /// метрик (X-Visitor-Id): по нему сервер дедуплицирует просмотры.
  ///
  /// [readBody] — прочитать тело ответа (JSON) и передать в
  /// [onResponse]. Нужен для различения ошибок сервера: хук
  /// «один ответ с устройства» отвечает 400 с текстом «Вы уже
  /// отвечали…», а сеть без тела — просто false.
  Future<bool> postJson(
    String url,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
    String? visitorId,
    void Function(int statusCode, Map<String, dynamic> json)? onResponse,
  }) async {
    try {
      final request = await _client.postUrl(Uri.parse(url)).timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (visitorId != null) {
        request.headers.set('X-Visitor-Id', visitorId);
      }
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      if (onResponse != null) {
        try {
          final text = await response.transform(utf8.decoder).join();
          if (text.trim().startsWith('{')) {
            onResponse(
              response.statusCode,
              Map<String, dynamic>.from(jsonDecode(text) as Map),
            );
          } else {
            onResponse(response.statusCode, const {});
          }
          return response.statusCode >= 200 && response.statusCode < 300;
        } catch (_) {
          return response.statusCode >= 200 && response.statusCode < 300;
        }
      }
      // Вычитываем тело, чтобы соединение вернулось в пул.
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

/// Виджет загрузки картинки через глобальный AppHttpClient.
class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage({
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
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
      _bytes = null;
    });

    // Кэш включён: это картинка — скролл не перезагружает байты.
    final bytes =
        await AppHttpClient.instance.fetchBytes(widget.url, cache: true);
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
