import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/post_card.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Профиль организатора: кто публикует, как связаться, что он предлагает.
///
/// Организация передаётся объектом (её уже знает страница организаций),
/// а «Предложения» запрашиваются отдельно по `organization` — лента тут
/// не причём: пользователь мог не открывать вкладок, где она грузится.
class OrgScreen extends ConsumerStatefulWidget {
  const OrgScreen({super.key, required this.organization});

  final Organization organization;

  @override
  ConsumerState<OrgScreen> createState() => _OrgScreenState();
}

class _OrgScreenState extends ConsumerState<OrgScreen> {
  List<Post>? _posts;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
    });
    try {
      final posts = await ref
          .read(postsRepoProvider)
          .fetchPosts(organizationId: widget.organization.id);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.organization;
    final favorites = ref.watch(favoritesProvider);
    final own = priorityFirst(_posts ?? const <Post>[]);

    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Организация'),
        titleTextStyle: AppText.headline,
        leading: const GlassBackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: AppScroll.plain,
              padding: EdgeInsets.fromLTRB(
                  pad, 8, pad, AppInsets.screenBottom(context)),
              children: [
                _Header(org: org, postCount: own.length),
                if ((org.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(org.description!,
                      style: AppText.body.copyWith(height: 1.45)),
                ],
                const SizedBox(height: 24),
                _Contacts(org: org),
                const SizedBox(height: 28),
                Text('Предложения', style: AppText.title),
                const SizedBox(height: 12),
                if (_offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Не удалось загрузить предложения — проверьте сеть',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ),
                if (own.isEmpty && !_offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Пока нет опубликованных предложений',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ),
                for (final p in own) ...[
                  PostCard(
                    post: p,
                    isFavorite: favorites.contains(p.id),
                    onTap: () => Navigator.of(context).push(
                      appRoute(context, PostDetailScreen(post: p)),
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
    final initial = org.name.trim().isEmpty
        ? '—'
        : org.name.trim().substring(0, 1).toUpperCase();

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
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: AppText.title
                  .copyWith(color: AppColors.secondaryLight, fontSize: 24)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(org.name, style: AppText.title),
              const SizedBox(height: 4),
              Text(
                org.isPartner ? 'Партнёр' : 'Подразделение вуза',
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
              const SizedBox(height: 4),
              Text(
                '$postCount ${_plural(postCount)}',
                style: AppText.caption.copyWith(color: AppColors.secondaryLight),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _plural(int n) => switch (n) {
        1 => 'предложение',
        2 || 3 || 4 => 'предложения',
        _ => 'предложений',
      };
}

class _Contacts extends StatelessWidget {
  const _Contacts({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String?)>[
      if ((org.website ?? '').isNotEmpty)
        (Icons.language_rounded, 'Сайт', org.website),
      if ((org.contactEmail ?? '').isNotEmpty)
        (Icons.mail_outline_rounded, 'Почта', org.contactEmail),
      if ((org.contactPhone ?? '').isNotEmpty)
        (Icons.phone_rounded, 'Телефон', org.contactPhone),
      if ((org.contactName ?? '').isNotEmpty)
        (Icons.person_outline_rounded, 'Контакт', org.contactName),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Контакты', style: AppText.title),
        const SizedBox(height: 12),
        for (final (icon, label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppText.caption
                              .copyWith(color: AppColors.secondaryLight)),
                      Text(value!, style: AppText.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
