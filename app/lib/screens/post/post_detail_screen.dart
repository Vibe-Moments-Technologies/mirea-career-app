import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_route.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/post_image.dart';
import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../org/org_screen.dart';

/// Экран деталей события.
///
/// Структура подчинена вопросу «пойду ли я и что для этого сделать»:
///  1. обложка с закреплённой шапкой — «назад» и избранное всегда под рукой,
///     шапка pinned, поэтому сохранить можно не листая обратно наверх;
///  2. тип, срочность и заголовок — читается первым;
///  3. организатор — кто стоит за предложением;
///  4. панель «Ключевое» — когда, дедлайн, формат, кампус, аудитория.
///     Раньше те же данные лежали разноцветными чипами вперемешку: тип,
///     формат, дата и институт выглядели одинаково важными и их приходилось
///     расшифровывать. Теперь у каждого факта есть подпись;
///  5. описание и теги;
///  6. счётчики — в конце: это справочная, а не решающая информация.
///
/// Кнопка действия закреплена внизу экрана: она не уезжает вместе с текстом
/// и не заставляет листать обратно после прочтения описания.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(metricsProvider).registerView(widget.post.id).then((counted) {
        if (counted && mounted) {
          ref.read(feedProvider.notifier).bumpViews(widget.post.id);
        }
      });
    });
  }

  static Future<void> _launchLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.mediumImpact();
    final added =
        await ref.read(favoritesProvider.notifier).toggle(widget.post.id);
    ref.read(metricsProvider).registerFavorite(widget.post.id, added ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final scheme = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoritesProvider);
    final isFav = favorites.contains(post.id);
    final link = post.externalLink?.trim() ?? '';
    final hasLink = link.isNotEmpty;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      // Закреплённое действие: bottomNavigationBar держит кнопку над
      // системной панелью и не даёт контенту прятаться под неё.
      bottomNavigationBar: hasLink
          ? _ActionBar(
              label: 'Перейти к регистрации',
              onTap: () => _launchLink(link),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: scheme.surface.withValues(alpha: 0.94),
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: const GlassBackButton(),
            actions: [
              GlassIconButton(
                icon: isFav
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: isFav ? scheme.primary : Colors.white,
                tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
                onTap: _toggleFavorite,
              ),
              const SizedBox(width: 6),
            ],
            flexibleSpace: FlexibleSpaceBar(background: _Cover(post: post)),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pad,
              20,
              pad,
              // С закреплённой панелью нижний safe-area уже занят ею.
              hasLink ? 24 : AppInsets.screenBottom(context),
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _TypeRow(post: post),
                const SizedBox(height: 12),
                Text(post.title,
                    style: AppText.largeTitle.copyWith(fontSize: 28)),
                const SizedBox(height: 18),
                _Organizer(post: post),
                _FactsPanel(post: post),
                if (post.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const _SectionTitle('Описание'),
                  const SizedBox(height: 10),
                  _Description(text: post.description),
                ],
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _SectionTitle('Теги'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in post.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text('#$t',
                              style: AppText.footnote
                                  .copyWith(color: scheme.primary)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 26),
                _Stats(post: post),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Обложка с затемнением под кнопки шапки.
class _Cover extends StatelessWidget {
  const _Cover({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Та же обложка, что в ленте и витрине: фото → буквенная заглушка.
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
              colors: [Color(0x66000000), Color(0x11000000)],
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка над заголовком: тип предложения и срочность.
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final urgent = urgencyLabel(post.endDate);
    final past = pastLabel(post.endDate);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.forPostType(post.type, brightness),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                (Catalogs.postTypes[post.type] ?? post.type).toUpperCase(),
                style: AppText.caption.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        // Срочность — только когда дедлайн близко; для завершившегося —
        // спокойная серая плашка «завершилось N дней назад».
        if (urgent != null)
          _Pill(icon: Icons.bolt_rounded, text: urgent, color: AppColors.warning)
        else if (past != null)
          _Pill(
            icon: Icons.archive_rounded,
            text: past,
            color: AppColors.secondaryLight,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              text,
              style: AppText.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

/// Панель «Ключевое»: факты с подписями, а не обезличенные чипы.
///
/// Пустые факты не показываются вовсе: строка «Кампус: не указан» учит
/// читателя пропускать панель целиком, а нужно обратное.
class _FactsPanel extends StatelessWidget {
  const _FactsPanel({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final range = dateRange(post.startDate, post.endDate);
    final rows = <_Fact>[
      // «Когда» имеет смысл только при указанном начале: иначе дата окончания
      // уже показана строкой «Заканчивается» и дублировалась бы.
      if (post.startDate != null && range != null)
        _Fact(Icons.event_rounded, 'Когда', range),
      if (post.endDate != null)
        _Fact(
          Icons.hourglass_bottom_rounded,
          'Заканчивается',
          dateWithTime(post.endDate!),
        ),
      if (Catalogs.formats[post.format] != null)
        _Fact(_formatIcon(post.format), 'Формат', Catalogs.formats[post.format]!),
      if (post.campuses.isNotEmpty)
        _Fact(
          Icons.place_rounded,
          post.campuses.length > 1 ? 'Кампусы' : 'Кампус',
          post.campuses.map(Catalogs.campusTitle).join(', '),
        ),
      if (post.institutes.isNotEmpty)
        _Fact(
          Icons.school_rounded,
          'Для кого',
          post.institutes.map(Catalogs.instituteTitle).join(', '),
        ),
      if (post.directions.isNotEmpty)
        _Fact(Icons.explore_rounded, 'Направления', post.directions.join(', ')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.separator(context)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: AppColors.separator(context)),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  IconData _formatIcon(String format) => switch (format) {
        'online' => Icons.videocam_rounded,
        'hybrid' => Icons.sync_alt_rounded,
        _ => Icons.location_city_rounded,
      };
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppText.caption.copyWith(
                    color: AppColors.secondaryLight,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value, style: AppText.body.copyWith(height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppText.section.copyWith(color: AppColors.secondaryLight),
      );
}

/// Организатор: карточка-ссылка на его профиль.
class _Organizer extends StatelessWidget {
  const _Organizer({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final org = post.organization;
    final name = post.organizationName?.trim() ?? '';

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Ведёт на профиль организатора: там контакты и все его предложения.
        // Организация собирается из вложенных полей поста — она уже известна,
        // отдельный запрос не нужен. Если организатора в посте нет,
        // карточка остаётся, но не кликабельна.
        onTap: org == null
            ? null
            : () => Navigator.of(context).push(
                  appRoute(context, OrgScreen(organization: org)),
                ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _OrgAvatar(initial: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Организатор не указан' : name,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.isPartner ? 'Компания-партнёр' : 'Подразделение вуза',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ],
                ),
              ),
              if (org != null)
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.secondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Аватар организатора — буква на нейтральной подложке.
///
/// Логотипы в данных пустые или внешние (placehold.co отдаёт 403), поэтому
/// серый квадрат на месте логотипа выглядел как баг. См. post_image.dart.
class _OrgAvatar extends StatelessWidget {
  const _OrgAvatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final letter = initial.isEmpty ? '—' : initial.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.placeholder(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: AppText.title
            .copyWith(color: AppColors.secondaryLight, fontSize: 19),
      ),
    );
  }
}

/// Счётчики — справочная информация в конце страницы.
class _Stats extends ConsumerWidget {
  const _Stats({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Счётчики берём из ленты: там же мгновенно отражаются изменения.
    final live = ref.watch(feedProvider).posts.firstWhere(
          (p) => p.id == post.id,
          orElse: () => post,
        );

    return Row(
      children: [
        _StatItem(
          icon: Icons.visibility_rounded,
          value: live.viewsCount,
          label: plural(live.viewsCount, 'просмотр', 'просмотра', 'просмотров'),
        ),
        const SizedBox(width: 24),
        _StatItem(
          icon: Icons.bookmark_rounded,
          value: live.favoritesCount,
          label: 'в избранном',
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.secondaryLight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: muted),
        const SizedBox(width: 6),
        Text('$value',
            style: AppText.footnote.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(width: 4),
        Text(label, style: AppText.footnote.copyWith(color: muted)),
      ],
    );
  }
}

/// Закреплённая внизу панель действия.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.separator(context))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: Text(label),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Описание: абзацы и списки из HTML-редактора PocketBase.
///
/// Поле `description` в БД — тип editor, то есть HTML. Раньше текст
/// выводился как есть, и любая разметка админа показывалась студенту
/// тегами. Полноценный рендер HTML не нужен: достаточно снять теги,
/// превратив блочные в переносы строк, и распаковать базовые сущности.
/// ponytail: без flutter_html — пакет ради трёх тегов не стоит,
/// а свой преобразователь здесь на двадцать строк.
class _Description extends StatelessWidget {
  const _Description({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in _toParagraphs(text))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(p, style: AppText.body.copyWith(height: 1.45)),
          ),
      ],
    );
  }

  /// HTML → список абзацев.
  static List<String> _toParagraphs(String html) {
    var s = html
        // <br> — перенос внутри абзаца
        .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
        // конец блока — граница абзаца: два переноса, иначе соседние <p>
        // сливались в один Text и абзацы не разделялись
        .replaceAll(
          RegExp(r'</\s*(p|div|li|ul|ol|h[1-6]|blockquote)\s*>',
              caseSensitive: false),
          '\n\n',
        )
        .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '\n• ')
        // остальные теги просто снимаем
        .replaceAll(RegExp(r'<[^>]*>'), '');

    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('**', '');

    return s
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }
}
