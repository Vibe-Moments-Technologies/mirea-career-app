import 'package:flutter/material.dart';

/// Плавное появление контента, который приехал из сети.
///
/// Скелетоны держат форму будущих карточек, а данные «проявляются» вместо
/// скачка: список не дёргается, когда лента пришла целиком.
///
/// ponytail: без пакета анимаций и без искусственной задержки. Таймер внутри
/// кадра оставлял бы висящий `Timer`, из-за которого ломаются тесты с
/// `scrollUntilVisible` (FakeAsync видит незавершённую задачу). Каскад даёт
/// сам скролл: элементы ниже монтируются позже и проявляются при появлении.
class RevealOnMount extends StatefulWidget {
  const RevealOnMount({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
  });

  final Widget child;
  final Duration duration;

  @override
  State<RevealOnMount> createState() => _RevealOnMountState();
}

class _RevealOnMountState extends State<RevealOnMount> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    // Первый кадр — прозрачно, следующий — с анимацией: иначе переход
    // применился бы сразу при монтировании и его не было бы видно.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
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
        offset: _shown ? Offset.zero : const Offset(0, 0.03),
        child: widget.child,
      ),
    );
  }
}
