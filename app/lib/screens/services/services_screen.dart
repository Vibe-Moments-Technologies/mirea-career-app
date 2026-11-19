import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../archive/archive_screen.dart';
import '../org/organizations_screen.dart';
import 'calendar_service_screen.dart';

/// Вкладка «Сервисы»: список доступных сервисов.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return PinnedHeaderScreen(
      title: 'Сервисы',
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.scrollBottom(context)),
          sliver: SliverList.list(
            children: [
              _ServiceTile(
                icon: Icons.calendar_month_rounded,
                title: 'Календарь',
                subtitle: 'События и важные даты',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const CalendarServiceScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _ServiceTile(
                icon: Icons.history_rounded,
                title: 'Архив',
                subtitle: 'Завершённые вакансии, события и стажировки',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const ArchiveScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _ServiceTile(
                icon: Icons.apartment_rounded,
                title: 'Организации',
                subtitle: 'Компании-партнёры и подразделения вуза',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const OrganizationsScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
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
