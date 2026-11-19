import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import 'calendar_service_screen.dart';

/// Вкладка «Сервисы»: список доступных сервисов.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          pad,
          12,
          pad,
          AppInsets.scrollBottom(context),
        ),
        children: [
          const ScreenTitle('Сервисы'),
          const SizedBox(height: 16),
          _ServiceTile(
            icon: Icons.calendar_month_rounded,
            title: 'Календарь',
            subtitle: 'События и важные даты',
            onTap: () => Navigator.of(context).push(
              appRoute(context, const CalendarServiceScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.headline),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
