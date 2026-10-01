import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/crash_reporting.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';

/// Индекс слайда для физически бесконечного `PageView`.
///
/// Возвращает остаток от деления, поэтому после последнего слайда идёт
/// первый, а не дотягивание за край с возвратом. Стартовая страница кратна
/// всем допустимым размерам витрины (2–5 слайдов).
int spotlightIndex(int page, int count) {
  assert(count > 0, 'в витрине должен быть хотя бы один слайд');
  return page % count;
}

/// Витрина главной: баннеры, которые листаются сами.
///
/// Это **отдельная сущность**, а не выборка постов: слайды создаёт
/// администратор в консоли (`spotlight_banners`), поэтому баннер не попадает
/// в ленту и не требует помечать обычную карточку «приоритетной».
///
/// Если слайдов нет, витрина не строится — пустой блок выше ленты только
/// отнимал бы экран.
class SpotlightGallery extends StatefulWidget {
  const SpotlightGallery({
    super.key,
    required this.banners,
  });

  final List<SpotlightBanner> banners;

  @override
  State<SpotlightGallery> createState() => _SpotlightGalleryState();
}

class _SpotlightGalleryState extends State<SpotlightGallery> {
  static const _period = Duration(seconds: 5);
  static const _height = 150.0;

  // Физически бесконечный ряд начинается кратно 2, 3, 4 и 5: первый кадр
  // всегда логический ноль, а границ у PageView просто нет.
  static const _startPage = 60000;

  late final PageController _controller = PageController(
    viewportFraction: 0.86,
    initialPage: _startPage,
  );
  Timer? _timer;
  late int _page = spotlightIndex(_startPage, widget.banners.length);

  /// Автолистание включается от двух слайдов: один и так виден целиком.
  /// Заодно это не мешает тестам — без таймера анимации нет и
  /// `pumpAndSettle` не зависает.
  bool get _autoScroll => widget.banners.length > 1;

  @override
  void initState() {
    super.initState();
    if (_autoScroll) _start();
  }

  @override
  void didUpdateWidget(SpotlightGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.banners.length != oldWidget.banners.length &&
        widget.banners.isNotEmpty) {
      // Физическая позиция контроллера остаётся, нормализуем только точку.
      _page = spotlightIndex(_page, widget.banners.length);
    }
    if (_autoScroll) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (_timer != null || !_autoScroll) return;
    _timer = Timer.periodic(_period, (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.banners.length;
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: PageView.builder(
            controller: _controller,
            // Активная карточка всегда по центру, по бокам — одинаковые
            // половинки соседних. При `padEnds: false` первая прижималась к
            // краю: слева щели нет, справа большая, и лента перестаёт
            // выглядеть бесконечной. Это верно и для двух слайдов: ряд
            // виртуально бесконечный, поэтому сосед есть с обеих сторон.
            padEnds: true,
            // itemCount нет намеренно: физический ряд бесконечный, поэтому
            // таймер не может упереться в последнюю страницу и отпружинить.
            onPageChanged: (i) =>
                setState(() => _page = spotlightIndex(i, count)),
            itemBuilder: (_, i) => Padding(
              // Одинаковые боковые поля у всех карточек: размер не зависит
              // от позиции, поэтому активная не «дышит».
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _Card(banner: widget.banners[spotlightIndex(i, count)]),
            ),
          ),
        ),
        if (_autoScroll) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.separator(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Карточка витрины: обложка, заголовок, подпись. Тап ведёт по ссылке, если
/// администратор её задал.
class _Card extends StatelessWidget {
  const _Card({required this.banner});

  final SpotlightBanner banner;

  Future<void> _open() async {
    final link = banner.linkUrl;
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasLink = (banner.linkUrl ?? '').isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: AppShadows.card(brightness),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: InkWell(
            onTap: hasLink ? _open : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(banner: banner),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.35, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        banner.title,
                        style: AppText.cardTitle.copyWith(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((banner.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          banner.subtitle!,
                          style: AppText.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasLink)
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: _OpenBadge(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.open_in_new_rounded,
            size: 14, color: Colors.white),
      );
}

/// Обложка баннера. Правила те же, что у постов (см. post_image.dart):
/// фото → ровная заглушка, без иконок поверх недогруженного кадра.
class _Cover extends StatelessWidget {
  const _Cover({required this.banner});
  final SpotlightBanner banner;

  @override
  Widget build(BuildContext context) {
    final place = ColoredBox(
      color: AppColors.placeholder(Theme.of(context).brightness),
      child: Center(
        child: Icon(
          Icons.campaign_rounded,
          size: 30,
          color: AppColors.secondaryLight,
        ),
      ),
    );

    final url = banner.imageUrl;
    if (url == null || url.isEmpty) return place;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: (width * dpr).round().clamp(64, 2048),
      loadingBuilder: (_, child, progress) => progress == null ? child : place,
      errorBuilder: (_, error, stack) {
        CrashReporting.report(
          error,
          stack ?? StackTrace.current,
          context: 'spotlight_cover_load:$url',
        );
        return place;
      },
    );
  }
}
