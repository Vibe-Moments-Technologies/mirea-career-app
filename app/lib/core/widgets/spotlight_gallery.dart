import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

/// Индекс витрины для физически бесконечного `PageView`.
///
/// Возвращает остаток от деления, поэтому после последнего слайда идёт
/// первый, а не дотягивание за край с возвратом. Стартовая страница кратна
/// всем допустимым размерам галереи (2–5 слайдов).
int spotlightIndex(int page, int count) {
  assert(count > 0, 'в витрине должен быть хотя бы один пост');
  return page % count;
}

/// Витрина важного: небольшие карточки, листающиеся сами.
///
/// Источник — приоритетные посты (их ставит главный модератор): это и есть
/// «новости и важная информация». Если таких нет, витрина не строится —
/// пустой блок выше ленты только отнимал бы экран.
class SpotlightGallery extends StatefulWidget {
  const SpotlightGallery({
    super.key,
    required this.posts,
    required this.onOpen,
  });

  final List<Post> posts;
  final ValueChanged<Post> onOpen;

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
  late int _page = spotlightIndex(_startPage, widget.posts.length);

  /// Автолистание включается только от двух карточек: одна и так видна
  /// целиком, а листать нечего. Заодно это не мешает тестам — без таймера
  /// анимации нет и `pumpAndSettle` не зависает.
  bool get _autoScroll => widget.posts.length > 1;

  @override
  void initState() {
    super.initState();
    if (_autoScroll) _start();
  }

  @override
  void didUpdateWidget(SpotlightGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.posts.length != oldWidget.posts.length && widget.posts.isNotEmpty) {
      // Физическая позиция контроллера остаётся, нормализуем только точку.
      _page = spotlightIndex(_page, widget.posts.length);
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
    final count = widget.posts.length;
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: PageView.builder(
            controller: _controller,
            // Активная карточка всегда по центру, по бокам — одинаковые
            // половинки соседних. При `padEnds: false` первая прижималась к
            // краю: слева щели нет, справа большая, и лента перестаёт
            // выглядеть бесконечной. Это верно и для двух карточек: ряд
            // виртуально бесконечный, поэтому сосед есть с обеих сторон.
            padEnds: true,
            // itemCount нет намеренно: физический ряд бесконечный, поэтому
            // таймер не может упереться в последнюю страницу и отпружинить.
            onPageChanged: (i) =>
                setState(() => _page = spotlightIndex(i, count)),
            itemBuilder: (_, i) {
              final index = spotlightIndex(i, count);
              final post = widget.posts[index];
              return Padding(
                // Одинаковые боковые поля у всех карточек: размер не
                // зависит от позиции, поэтому активная не «дышит».
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _Card(
                  post: post,
                  onTap: () => widget.onOpen(post),
                ),
              );
            },
          ),
        ),
        if (_autoScroll) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.posts.length; i++)
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

/// Компактная карточка витрины: фото, заголовок и источник.
class _Card extends StatelessWidget {
  const _Card({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final organization = (post.organizationName ?? '').trim();

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
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PostCover(
                  post: post,
                  size: null,
                  borderRadius: BorderRadius.zero,
                  letter: true,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.4, 1],
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
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Приоритет',
                            style: AppText.caption.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                      if (organization.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          organization,
                          style: AppText.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        post.title,
                        style: AppText.cardTitle.copyWith(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}