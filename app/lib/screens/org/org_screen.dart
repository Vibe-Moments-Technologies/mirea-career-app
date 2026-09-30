import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Профиль организатора: кто публикует, как связаться, что он предлагает.
///
/// Данные берутся из уже загруженной ленты — организация приходит вложенно
/// в каждом посте (`_select` в posts_repo), отдельного запроса к БД не нужно.
/// Если постов организации в текущей ленте нет (например, всё отфильтровано
/// на сервере), показываем то, что знаем, без пустого экрана.
class OrgScreen extends ConsumerWidget {
  const OrgScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedProvider).posts;
    final favorites = ref.watch(favoritesProvider);
    // Приоритетные (is_featured) — вверху, как на главной и в каталоге.
    final own = priorityFirst(
      posts.where((p) => p.organizationId == organizationId).toList(),
    );
    final org = own.isNotEmpty ? own.first.organization : null;

    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(title: const Text('Организация')),
      body: org == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Организация недоступна',
                  style: AppText.headline,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.screenBottom(context)),
              children: [
                _Header(org: org, postCount: own.length),
                if ((org.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(org.description!, style: AppText.body.copyWith(height: 1.45)),
                ],
                const SizedBox(height: 24),
                _Contacts(org: org),
                const SizedBox(height: 28),
                Text('Предложения', style: AppText.title),
                const SizedBox(height: 12),
                for (final p in own) ...[
                  PostCard(
                    post: p,
                    isFavorite: favorites.contains(p.id),
                    onTap: () => Navigator.of(context).push(
                      appRoute(context, PostDetailScreen(post: p))
                    ),
                    onToggleFavorite: () async {
                      final added =
                          await ref.read(favoritesProvider.notifier).toggle(p.id);
                      await ref
                          .read(metricsProvider)
                          .registerFavorite(p.id, added ? 1 : -1);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.org, required this.postCount});
  final Organization org;
  final int postCount;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final initial = org.name.trim().isEmpty ? '—' : org.name.trim().substring(0, 1).toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Логотипы в демо — placehold.co (403), поэтому буква вместо картинки:
        // серый квадрат на месте логотипа выглядел как баг.
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.placeholder(brightness),
            borderRadius: BorderRadius.circular(AppRadius.thumb),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: AppText.largeTitle.copyWith(color: AppColors.secondaryLight),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(org.name, style: AppText.title),
              const SizedBox(height: 4),
              Text(
                org.isPartner ? 'Компания-партнёр' : 'Подразделение вуза',
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
              const SizedBox(height: 6),
              Text(
                '$postCount ${_plural(postCount)} в приложении',
                style: AppText.caption.copyWith(color: AppColors.secondaryLight),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _plural(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'предложение';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'предложения';
    return 'предложений';
  }
}

/// Контакты организатора. Показываем только то, что реально заполнено —
/// пустых строк «Телефон: —» быть не должно.
class _Contacts extends StatelessWidget {
  const _Contacts({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if ((org.contactName ?? '').isNotEmpty)
        _row(context, Icons.badge_outlined, 'Контактное лицо', org.contactName!),
      if ((org.contactEmail ?? '').isNotEmpty)
        _row(
          context,
          Icons.mail_outline_rounded,
          'Почта',
          org.contactEmail!,
          onTap: () => _launch(context, 'mailto:${org.contactEmail}'),
        ),
      if ((org.contactPhone ?? '').isNotEmpty)
        _row(
          context,
          Icons.call_outlined,
          'Телефон',
          org.contactPhone!,
          onTap: () => _launch(context, 'tel:${_digits(org.contactPhone!)}'),
        ),
      if ((org.website ?? '').isNotEmpty)
        _row(
          context,
          Icons.language_rounded,
          'Сайт',
          _prettyUrl(org.website!),
          onTap: () => _launch(context, org.website!),
        ),
    ];

    if (rows.isEmpty) {
      return Text(
        'Контакты не указаны',
        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(height: 1, indent: 52, color: AppColors.separator(context)),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: onTap != null ? scheme.primary : AppColors.secondaryLight),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.caption.copyWith(color: AppColors.secondaryLight),
                  ),
                  Text(
                    value,
                    style: AppText.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.secondaryLight),
          ],
        ),
      ),
    );
  }

  /// Внешний браузер / почта / звонилка — как и кнопка регистрации (UI.md §7).
  static Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // нет приложения для tel:/mailto: — молча ничего, экран не ломается
    }
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  static String _prettyUrl(String url) =>
      url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
}
