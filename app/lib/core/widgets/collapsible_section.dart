import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Раскрывающаяся секция — общая для всех панелей фильтров.
///
/// В каталоге и на странице организаций группы фильтров устроены одинаково:
/// заголовок-строкой, по тапу раскрывается содержимое. Раньше это было
/// приватным классом каталога, и второй экран завёл бы себе копию.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
    this.open,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  /// Открыть по наличию выбранных значений (управляется снаружи).
  final bool? open;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded = widget.initiallyOpen || (widget.open ?? false);

  @override
  Widget build(BuildContext context) {
    // внешний флаг важнее: выбрали фильтр — секция обязана раскрыться
    final expanded = widget.open == true || _expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !expanded),
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: AppText.section.copyWith(
                      color: AppColors.secondaryLight,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded,
                      color: AppColors.secondaryLight),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
