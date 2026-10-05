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
  /// Результат кэшируется в памяти: повторные вызовы для того же URL
  /// возвращают байты мгновенно, без HTTP-запроса.
  /// При ошибке делает одну повторную попытку.
  Future<Uint8List?> fetchBytes(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Кэш: если уже загружали — возвращаем сразу.
    final cached = _imageCache[url];
    if (cached != null) return cached;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request =
            await _client.getUrl(Uri.parse(url)).timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode != 200) continue;
        final chunks = <int>[];
        await for (final chunk in response.timeout(timeout)) {
          chunks.addAll(chunk);
        }
        final bytes = Uint8List.fromList(chunks);
        _imageCache[url] = bytes;
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
