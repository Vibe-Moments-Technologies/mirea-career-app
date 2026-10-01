import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

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

  final _controller = PageController(viewportFraction: 0.86);
  Timer? _timer;
  int _page = 0;

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
    if (widget.posts.length > 1 && !_autoScroll) _start();
    if (widget.posts.length <= 1) _stop();
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
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
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: widget.posts.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? pad : 6,
                right: i == widget.posts.length - 1 ? pad : 6,
              ),
              child: _Card(
                post: widget.posts[i],
                onTap: () => widget.onOpen(widget.posts[i]),
              ),
            ),
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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
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
                        'Важное',
                        style: AppText.caption.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.title,
                    style: AppText.headline.copyWith(color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}