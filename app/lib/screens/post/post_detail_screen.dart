import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_route.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/markdown_body.dart';
import '../../core/widgets/post_image.dart';
import '../../data/app_http_client.dart';
import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../form/form_screen.dart';
import '../org/org_screen.dart';

/// Экран деталей события.
///
/// Структура подчинена вопросу «пойду ли я и что для этого сделать»:
///  1. обложка с закреплённой шапкой — «назад» и избранное всегда под рукой,
///     шапка pinned, поэтому сохранить можно не листая обратно наверх;
///  2. тип, срочность и заголовок — читается первым;
///  3. организатор — кто стоит за предложением;
///  4. кнопка отклика — сразу за организатором: кто предлагает, уже известно;
///  5. панель «Ключевое» — когда, дедлайн, формат, кампус, аудитория.
///     Раньше те же данные лежали разноцветными чипами вперемешку: тип,
///     формат, дата и институт выглядели одинаково важными и их приходилось
///     расшифровывать. Теперь у каждого факта есть подпись;
///  6. описание и теги;
///  7. счётчики — в конце: это справочная, а не решающая информация.
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
    final form = post.form;
    final isSurvey = post.type == 'survey';
    // Анкета приоритетнее внешней ссылки: опросник в приложении
    // открывает прямой канал отклика (ответ летит в БД), а ссылка —
    // браузер с чужой регистрацией.
    // Опрос — карточка вуза с анкетой внутри: кнопка зовёт «Пройти опрос»,
    // внешняя ссылка ему не нужна.
    // Заполненная анкета блокируется повторно: история на устройстве
    // знает, что уже отправлено, и кнопка сразу показывает это.
    final filledForm =
        form != null && ref.watch(hasSubmittedProvider(post.id));
    final applyLabel = isSurvey
        ? (filledForm ? 'Опрос пройден' : 'Пройти опрос')
        : (filledForm ? 'Анкета заполнена' : 'Заполнить анкету');
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
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
                // Избранное = звезда везде: и здесь, и в ленте, и в доке.
                icon: isFav
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
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
              AppInsets.screenBottom(context),
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _MetaRow(post: post),
                const SizedBox(height: 12),
                Text(post.title,
                    style: AppText.largeTitle.copyWith(fontSize: 28)),
                const SizedBox(height: 18),
                _Organizer(post: post),
                // Действие сразу после организатора: к этому моменту студент
                // уже знает, кто предлагает, — и может откликнуться, не
                // листая описание. Анкета (если привязана) открывается
                // вместо внешней ссылки.
                if (form != null)
                  _ApplyButton(
                    label: applyLabel,
                    icon: filledForm
                        ? Icons.task_alt_rounded
                        : (isSurvey
                            ? Icons.poll_rounded
                            : Icons.description_outlined),
                    onTap: () => Navigator.of(context).push(
                      appRoute(
                        context,
                        FormScreen(
                          form: form,
                          postId: post.id,
                          postTitle: post.title,
                        ),
                      ),
                    ),
                  )
                else if (link.isNotEmpty)
                  _ApplyButton(
                      label: 'Перейти к регистрации',
                      onTap: () => _launchLink(link)),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Обложка с затемнением под кнопки шапки.
///
/// Если у поста есть галерея — свайп-слайдер: обложка первым слайдом,
/// дальше файлы gallery. Одна картинка (или пустая галерея) — просто
/// обложка, без точек и свайпа.
class _Cover extends StatefulWidget {
  const _Cover({required this.post});
  final Post post;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  PageController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final urls = post.galleryUrls;

    // Одна или ноль картинок — прежняя обложка: фото → буквенная заглушка.
    if (urls.length <= 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          PostCover(
            post: post,
            size: null,
            borderRadius: BorderRadius.zero,
            letter: true,
          ),
          const _CoverShade(),
        ],
      );
    }

    _controller ??= PageController();

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: urls.length,
          itemBuilder: (_, i) => AppNetworkImage(
            url: urls[i],
            fit: BoxFit.cover,
            placeholder: PostCover(
              post: post,
              size: null,
              borderRadius: BorderRadius.zero,
              letter: true,
            ),
            errorWidget: PostCover(
              post: post,
              size: null,
              borderRadius: BorderRadius.zero,
              letter: true,
            ),
          ),
        ),
        const _CoverShade(),
        // Точки-индикаторы поверх затемнения: видны и на светлом слайде.
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: AnimatedBuilder(
            animation: _controller!,
            builder: (_, _) {
              final page = _controller!.page?.round() ?? 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == page ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Затемнение обложки под кнопки шапки.
class _CoverShade extends StatelessWidget {
  const _CoverShade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66000000), Color(0x11000000)],
          ),
        ),
      );
}

/// Строка над заголовком: тип предложения и срочность.
/// Широкая мета-строка: тип · формат · просмотры · избранное · анкеты.
///
/// Всё мелкими значками со значением в один ряд (переносится на вторую
/// строку на узких экранах) — читается как «паспорт» карточки,
/// не перегружая верх (запрос: чипы наверху, статистика — сюда же).
class _MetaRow extends ConsumerWidget {
  const _MetaRow({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final urgent = urgencyLabel(post.endDate);
    final past = pastLabel(post.endDate);
    // Счётчики — из ленты: там мгновенно отражаются изменения.
    final live = ref.watch(feedProvider).posts.firstWhere(
          (p) => p.id == post.id,
          orElse: () => post,
        );

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
                Catalogs.postTypeTitle(post.type).toUpperCase(),
                style: AppText.caption.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        if (Catalogs.formats[post.format] != null)
          _Pill(
            icon: _formatIcon(post.format),
            text: Catalogs.formats[post.format]!,
            // Формат — своим цветом: онлайн/гибрид/офлайн различимы
            // до чтения, как тип поста своей точкой.
            color: _formatColor(post.format, context),
          ),
        // Срочность — только при близком дедлайне; завершившееся —
        // спокойная серая плашка.
        if (urgent != null)
          _Pill(icon: Icons.bolt_rounded, text: urgent, color: AppColors.warning)
        else if (past != null)
          _Pill(
            icon: Icons.archive_rounded,
            text: past,
            color: AppColors.secondaryLight,
          ),
        _CountPill(
            icon: Icons.visibility_rounded, value: live.viewsCount),
        _CountPill(icon: Icons.star_rounded, value: live.favoritesCount),
      ],
    );
  }

  IconData _formatIcon(String format) => switch (format) {
        'online' => Icons.videocam_rounded,
        'hybrid' => Icons.sync_alt_rounded,
        _ => Icons.location_city_rounded,
      };

  /// Цвет чипа формата: онлайн — зелёный (участие откуда угодно),
  /// гибрид — оранжевый (внимание: время и место), офлайн — синий
  /// (акцент приложения: «приехать нужно»).
  Color _formatColor(String format, BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (format) {
      'online' => AppColors.success,
      'hybrid' => AppColors.warning,
      _ => dark ? AppColors.accentDark : AppColors.accent,
    };
  }
}

/// Значок-счётчик: просмотры, избранное — с числом.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.value});
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.secondaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: muted),
          const SizedBox(width: 5),
          Text('$value',
              style: AppText.caption.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
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

/// Панель информации о событии.
///
/// Два смысловых блока дат (запрос): «Приём заявок до» (end_date —
/// дедлайн регистрации/анкеты) и «Проведение» (start_date, с диапазоном
/// нескольких дней). Формат НЕ дублируем — он в мета-строке чипов
/// сверху. Остальное: кампус, для кого, направления.
class _FactsPanel extends StatelessWidget {
  const _FactsPanel({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final range = dateRange(post.startDate, post.endDate);
    final rows = <_Fact>[
      // «Приём заявок/регистрации до» — end_date в роли дедлайна:
      // для мероприятий это край подачи, для вакансий — край отклика.
      if (post.endDate != null)
        _Fact(
          Icons.hourglass_bottom_rounded,
          'Приём заявок до',
          dateWithTime(post.endDate!),
        ),
      // «Проведение» — период самого события (может быть несколько дней).
      if (post.startDate != null)
        _Fact(
          Icons.event_rounded,
          'Проведение',
          range ?? dateWithTime(post.startDate!),
        ),
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

/// Организатор: карточка-ссылка на профиль организации.
class _Organizer extends StatelessWidget {
  const _Organizer({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Организация, иначе author_name (посты без организации из консоли).
    final name = post.authorLabel?.trim() ?? '';
    // Профиль открываем только для настоящей организации: author_name —
    // просто подпись без карточки в БД.
    final org = post.organization;

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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

/// Кнопка отклика — в потоке контента, сразу за блоком организатора.
///
/// Раньше она была закреплена внизу экрана: панель перекрывала часть
/// контента, съедала высоту и создавала вторую зону внимания рядом
/// с описанием. На своём месте в потоке она читается как шаг сценария
/// «узнал, кто предлагает → откликнулся».
class _ApplyButton extends StatelessWidget {
  const _ApplyButton({
    required this.onTap,
    this.label = 'Перейти к регистрации',
    this.icon = Icons.open_in_new_rounded,
  });
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ),
      );
}

/// Описание поста: Markdown из консоли.
///
/// Консоль пишет описания в Markdown (**жирный**, списки, заголовки,
/// ссылки). Раньше поле было HTML-редактором и разметку приходилось
/// снимать; теперь рендерим честно. ponytail: без flutter_markdown —
/// свой рендер на ~80 строк держит стиль приложения.
class _Description extends StatelessWidget {
  const _Description({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(text: text);
  }
}
