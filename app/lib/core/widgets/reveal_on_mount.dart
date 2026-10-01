import 'package:flutter/material.dart';

/// Плавное появление контента, который приехал из сети.
///
/// Скелетоны держат форму будущих карточек, а сами данные «проявляются»
/// вместо скачка: список не дёргается, когда лента пришла целиком.
/// ponytail: без пакета анимаций — одного AnimatedOpacity+Slide достаточно,
/// а каскад по индексу даёт эффект последовательной подгрузки.
class RevealOnMount extends StatefulWidget {
  const RevealOnMount({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// Порядковый номер элемента: даёт лёгкий каскад вместо одновременного
  /// появления всего списка.
  final int index;
  final Duration duration;

  /// Максимальная задержка каскада — дальше списка это превращается в
  /// ожидание и раздражает.
  static const maxStagger = Duration(milliseconds: 180);

  @override
  State<RevealOnMount> createState() => _RevealOnMountState();
}

class _RevealOnMountState extends State<RevealOnMount> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final stagger = Duration(
      milliseconds: (widget.index * 40).clamp(
        0,
        RevealOnMount.maxStagger.inMilliseconds,
      ),
    );
    // Первый кадр — прозрачно, второй — с анимацией: так переход реально
    // проигрывается, а не применяется сразу при монтировании.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (stagger > Duration.zero) await Future<void>.delayed(stagger);
      if (!mounted) return;
      setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: widget.duration,
      curve: Curves.easeOut,
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        offset: _shown ? Offset.zero : const Offset(0, 0.04),
        child: widget.child,
      ),
    );
  }
}
