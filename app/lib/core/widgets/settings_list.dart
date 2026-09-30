import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Группа пунктов в стиле iOS-настроек: карточка со скруглением,
/// внутри — строки, разделённые тонкой линией.
///
/// Общая для экранов «Ещё», «Настройки» и «О приложении», чтобы они
/// выглядели одинаково и не отращивали каждая свою копию.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final List<Widget> children;
  final String? title;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    // Material, а не Container с цветом: иначе ListTile не покажет
    // всплески нажатия и Flutter ругается в debug-сборке.
    final card = Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title!.toUpperCase(),
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
          ),
        card,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6, right: 4),
            child: Text(
              footer!,
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
          ),
      ],
    );
  }
}

/// Строка списка настроек.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? AppColors.danger : scheme.primary;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: AppText.headline.copyWith(color: danger ? AppColors.danger : null),
      ),
      subtitle: Text(
        subtitle,
        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryLight),
        ],
      ),
    );
  }
}

/// Строка без перехода — например, версия приложения.
class SettingsValueTile extends StatelessWidget {
  const SettingsValueTile({
    super.key,
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: AppText.headline),
      trailing: Text(
        value,
        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
      ),
    );
  }
}