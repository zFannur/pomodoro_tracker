import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/help_content.dart';
import '../../app/strings.dart';
import '../../domain/adoption.dart';
import '../cubits/activity_cubit.dart';
import '../cubits/directions_cubit.dart';
import '../cubits/insight_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../cubits/tasks_cubit.dart';
import '../home_shell.dart';
import 'settings_dialog.dart';

/// Имя маршрута справки: по нему «Открыть…» закрывает все её страницы сразу.
const _routeName = '/help';

/// Окно со справкой и с этой ширины включается двухколонный вид.
const _wideFrom = 900.0;

/// Индексы вкладок оболочки (кроме «Разбора» — это [kInsightTab]).
const _tabTimer = 0;
const _tabTasks = 1;
const _tabSprint = 2;
const _tabCourse = 3;
const _tabStats = 4;

/// Открыть справку. [section] — id раздела; без него широкое окно встаёт на
/// «С чего начать», а узкий экран показывает список разделов.
///
/// Кубиты берутся «если есть»: маршрут диалога может не видеть провайдеров
/// экрана (в приложении они выше `MaterialApp`, в тестах — внутри `home`), а
/// справка без данных всё равно читается, просто без автоотметок пути.
Future<void> showHelp(
  BuildContext context, {
  String? section,
  @visibleForTesting bool? isWindows,
}) {
  final env = _HelpEnv(
    origin: context,
    insight: _maybe<InsightCubit>(context),
    tasks: _maybe<TasksCubit>(context),
    directions: _maybe<DirectionsCubit>(context),
    activity: _maybe<ActivityCubit>(context),
    settings: _maybe<SettingsCubit>(context),
    windows: isWindows ?? Platform.isWindows,
  );
  if (MediaQuery.sizeOf(context).width >= _wideFrom) {
    return showDialog<void>(
      context: context,
      routeSettings: const RouteSettings(name: _routeName),
      builder: (_) => _HelpHost(
        env: env,
        child: _HelpDialog(initial: section ?? 'start'),
      ),
    );
  }
  final navigator = Navigator.of(context);
  final list = navigator.push<void>(
    _route(env, const _HelpList()),
  );
  if (section != null) {
    navigator.push<void>(_route(env, _SectionPage(id: section)));
  }
  return list;
}

Route<void> _route(_HelpEnv env, Widget page) => MaterialPageRoute<void>(
  settings: const RouteSettings(name: _routeName),
  builder: (_) => _HelpHost(env: env, child: page),
);

T? _maybe<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Маленькая «?» для заголовка экрана: открывает справку на нужном разделе.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: S.helpTitle,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.help_outline),
      onPressed: () => showHelp(context, section: section),
    );
  }
}

// ---------------------------------------------------------------------------
// Данные для окна: кубиты, факты пути, переходы
// ---------------------------------------------------------------------------

class _HelpEnv {
  const _HelpEnv({
    required this.origin,
    required this.insight,
    required this.tasks,
    required this.directions,
    required this.activity,
    required this.settings,
    required this.windows,
  });

  /// Контекст, из которого открыли справку: от него открываем настройки.
  final BuildContext origin;
  final InsightCubit? insight;
  final TasksCubit? tasks;
  final DirectionsCubit? directions;
  final ActivityCubit? activity;
  final SettingsCubit? settings;
  final bool windows;

  List<BlocBase<Object?>> get all => [
    ?insight,
    ?tasks,
    ?directions,
    ?activity,
    ?settings,
  ];
}

/// Собирает факты пути из кубитов и перестраивает окно при любом их
/// изменении (аналог `context.watch`, но кубитов может не быть в дереве).
class _HelpHost extends StatefulWidget {
  const _HelpHost({required this.env, required this.child});

  final _HelpEnv env;
  final Widget child;

  @override
  State<_HelpHost> createState() => _HelpHostState();
}

class _HelpHostState extends State<_HelpHost> {
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    for (final cubit in widget.env.all) {
      _subs.add(
        cubit.stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = widget.env;
    final settings = env.settings?.state.settings;
    final insight = env.insight?.state;
    final manual = {...?settings?.helpChecks};
    final facts = AdoptionFacts.collect(
      now: clock.now(),
      directions: env.directions?.state.directions ?? const [],
      milestones: env.directions?.state.milestones ?? const [],
      days: insight?.days ?? const [],
      todo: env.tasks?.state.todo ?? const [],
      sprint: insight?.sprint,
      previous: insight?.previous,
      settings: settings,
      hasDistractMarks: env.activity?.state.distracting.isNotEmpty ?? false,
    );
    final stages = adoptionStages();
    return _HelpScope(
      env: env,
      facts: facts,
      manual: manual,
      stages: stages,
      stage: currentStage(stages, facts, manual, windows: env.windows),
      child: widget.child,
    );
  }
}

class _HelpScope extends InheritedWidget {
  const _HelpScope({
    required this.env,
    required this.facts,
    required this.manual,
    required this.stages,
    required this.stage,
    required super.child,
  });

  final _HelpEnv env;
  final AdoptionFacts facts;
  final Set<String> manual;
  final List<HelpStage> stages;

  /// Индекс текущего этапа; `stages.length` — путь пройден.
  final int stage;

  static _HelpScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HelpScope>()!;

  @override
  bool updateShouldNotify(_HelpScope old) => true;

  bool get windows => env.windows;

  /// Шаги, которые показываются на этой платформе.
  List<HelpStep> visibleSteps(HelpStage stage) => [
    for (final s in stage.steps)
      if (windows || !s.windowsOnly) s,
  ];

  /// Доля выполненных обязательных шагов — для полоски в меню.
  double get progress {
    var done = 0;
    var total = 0;
    for (final st in stages) {
      for (final s in st.steps) {
        if (!stepRequired(s, windows: windows)) continue;
        total++;
        if (stepDone(s.id, facts, manual)) done++;
      }
    }
    return total == 0 ? 0 : done / total;
  }

  void toggleCheck(String id) {
    final cubit = env.settings;
    if (cubit == null) return;
    final checks = cubit.state.settings.helpChecks;
    cubit.update(
      cubit.state.settings.copyWith(
        helpChecks: checks.contains(id)
            ? [
                for (final c in checks)
                  if (c != id) c,
              ]
            : [...checks, id],
      ),
    );
  }

  /// Закрыть справку и открыть место, на которое ведёт [target].
  void go(BuildContext context, HelpTarget target) {
    Navigator.of(context).popUntil((r) => r.settings.name != _routeName);
    switch (target) {
      case HelpTarget.timer:
        homeTab.value = _tabTimer;
      case HelpTarget.tasks:
        homeTab.value = _tabTasks;
      case HelpTarget.sprint:
        homeTab.value = _tabSprint;
      case HelpTarget.course:
        homeTab.value = _tabCourse;
      case HelpTarget.stats:
        homeTab.value = _tabStats;
      case HelpTarget.review:
        _review(0);
      case HelpTarget.reviewEpisodes:
        _review(1);
      case HelpTarget.reviewWindows:
        _review(2);
      case HelpTarget.settingsTimer:
        _settings(kSettingsTabTimer);
      case HelpTarget.settingsNotify:
        _settings(kSettingsTabNotify);
      case HelpTarget.settingsApp:
        _settings(kSettingsTabApp);
      case HelpTarget.settingsAi:
        _settings(kSettingsTabAi);
    }
  }

  void _review(int sub) {
    // Подвкладку — раньше вкладки: «Разбор» уже построен и слушает её.
    insightSubTab.value = sub;
    homeTab.value = kInsightTab;
  }

  void _settings(int tab) {
    final origin = env.origin;
    if (origin.mounted) showSettingsDialog(origin, initialTab: tab);
  }
}

// ---------------------------------------------------------------------------
// Широкое окно
// ---------------------------------------------------------------------------

class _HelpDialog extends StatefulWidget {
  const _HelpDialog({required this.initial});

  final String initial;

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  final _search = TextEditingController();
  late String _selected = widget.initial;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final query = _search.text.trim();
    final shown = [
      for (final s in helpSections())
        if (sectionMatches(s, query)) s,
    ];
    final index = shown.indexWhere((s) => s.id == _selected);
    final current = shown.isEmpty ? null : shown[math.max(index, 0)];
    final at = math.max(index, 0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: math.min(960, size.width * 0.92),
            height: math.min(680, size.height * 0.92),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: _SearchField(
                          controller: _search,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final s in shown)
                              _MenuItem(
                                key: ValueKey('help-menu-${s.id}'),
                                section: s,
                                selected: s.id == current?.id,
                                onTap: () => setState(() => _selected = s.id),
                              ),
                          ],
                        ),
                      ),
                      _PathMini(onTap: () => setState(() {
                        _search.clear();
                        _selected = 'start';
                      })),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Stack(
                    children: [
                      if (current == null)
                        Center(
                          child: Text(
                            S.helpNothing,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        SingleChildScrollView(
                          key: ValueKey('help-body-${current.id}'),
                          padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SectionBody(
                                    section: current,
                                    query: query,
                                    large: true,
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      at > 0
                                          ? TextButton(
                                              key: const ValueKey('help-prev'),
                                              onPressed: () => setState(
                                                () => _selected =
                                                    shown[at - 1].id,
                                              ),
                                              child: Text(S.helpPrev),
                                            )
                                          : const SizedBox.shrink(),
                                      at < shown.length - 1
                                          ? TextButton(
                                              key: const ValueKey('help-next'),
                                              onPressed: () => setState(
                                                () => _selected =
                                                    shown[at + 1].id,
                                              ),
                                              child: Text(S.helpNext),
                                            )
                                          : const SizedBox.shrink(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          tooltip: S.close,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: S.helpSearch,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: S.close,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final HelpSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text(section.emoji),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Внедрение · этап 2 из 5» с полоской — внизу меню и первой карточкой на узком.
class _PathMini extends StatelessWidget {
  const _PathMini({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = _HelpScope.of(context);
    final theme = Theme.of(context);
    final total = scope.stages.length;
    final text = scope.stage >= total
        ? S.helpPathDone
        : S.helpPathProgress(scope.stage + 1, total);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: scope.progress,
                minHeight: 6,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Узкий экран
// ---------------------------------------------------------------------------

class _HelpList extends StatefulWidget {
  const _HelpList();

  @override
  State<_HelpList> createState() => _HelpListState();
}

class _HelpListState extends State<_HelpList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final shown = [
      for (final s in helpSections())
        if (sectionMatches(s, query)) s,
    ];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SearchField(controller: _search, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          if (query.isEmpty)
            Card(
              child: _PathMini(
                onTap: () => Navigator.of(
                  context,
                ).push<void>(_pageRoute(context, const _SectionPage(id: 'start'))),
              ),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  S.helpNothing,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                child: ListTile(
                  key: ValueKey('help-card-${s.id}'),
                  leading: Text(s.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(s.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    _pageRoute(context, _SectionPage(id: s.id, query: query)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Страница раздела внутри уже открытой справки: те же данные, что у списка.
Route<void> _pageRoute(BuildContext context, Widget page) =>
    _route(_HelpScope.of(context).env, page);

class _SectionPage extends StatelessWidget {
  const _SectionPage({required this.id, this.query = ''});

  final String id;
  final String query;

  @override
  Widget build(BuildContext context) {
    final sections = helpSections();
    final section = sections.firstWhere(
      (s) => s.id == id,
      orElse: () => sections.first,
    );
    return Scaffold(
      appBar: AppBar(title: Text('${section.emoji} ${section.title}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _SectionBody(section: section, query: query, large: false),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Блоки
// ---------------------------------------------------------------------------

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.query,
    required this.large,
  });

  final HelpSection section;
  final String query;

  /// Крупный заголовок раздела — в широком окне; на узком он в AppBar.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (large) ...[
          Padding(
            // Справа место под крестик.
            padding: const EdgeInsets.only(right: 40, bottom: 12),
            child: Text(
              '${section.emoji} ${section.title}',
              key: const ValueKey('help-title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        for (final block in section.blocks) _blockView(block, query),
      ],
    );
  }
}

Widget _blockView(HelpBlock block, String query) => switch (block) {
  Lead(:final text) => _LeadView(text, query),
  Para(:final text) => _ParaView(text, query),
  Heading(:final text) => _HeadingView(text, query),
  Steps(:final items) => _StepsView(items, query),
  Bullets(:final items) => _BulletsView(items, query),
  Compare(:final items) => _CompareView(items, query),
  Tip(:final text) => _CalloutView(text, query, warn: false),
  Warn(:final text) => _CalloutView(text, query, warn: true),
  Go(:final label, :final target) => _GoView(label, target),
  PathBlock() => _PathView(query),
  Sources() => const _SourcesView(),
};

final _inline = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');

/// Текст с `**жирным**`, `` `кодом` `` и подсветкой совпадений поиска.
List<InlineSpan> _spans(
  BuildContext context,
  String text,
  String query, {
  TextStyle? style,
}) {
  final scheme = Theme.of(context).colorScheme;
  final base = style ?? DefaultTextStyle.of(context).style;
  final spans = <InlineSpan>[];

  void add(String part, TextStyle partStyle) {
    if (part.isEmpty) return;
    final q = query.trim();
    if (q.isEmpty) {
      spans.add(TextSpan(text: part, style: partStyle));
      return;
    }
    var at = 0;
    for (final m in RegExp(
      RegExp.escape(q),
      caseSensitive: false,
    ).allMatches(part)) {
      if (m.start > at) {
        spans.add(TextSpan(text: part.substring(at, m.start), style: partStyle));
      }
      spans.add(
        TextSpan(
          text: m[0],
          style: partStyle.copyWith(
            backgroundColor: scheme.tertiaryContainer,
            color: scheme.onTertiaryContainer,
          ),
        ),
      );
      at = m.end;
    }
    if (at < part.length) {
      spans.add(TextSpan(text: part.substring(at), style: partStyle));
    }
  }

  var at = 0;
  for (final m in _inline.allMatches(text)) {
    add(text.substring(at, m.start), base);
    if (m[1] != null) {
      add(m[1]!, base.copyWith(fontWeight: FontWeight.w700));
    } else {
      add(
        m[2]!,
        base.copyWith(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['Courier New', 'monospace'],
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      );
    }
    at = m.end;
  }
  add(text.substring(at), base);
  return spans;
}

Widget _rich(
  BuildContext context,
  String text,
  String query, {
  TextStyle? style,
}) => Text.rich(
  TextSpan(children: _spans(context, text, query, style: style)),
  style: style,
);

class _LeadView extends StatelessWidget {
  const _LeadView(this.text, this.query);

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _rich(
        context,
        text,
        query,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _ParaView extends StatelessWidget {
  const _ParaView(this.text, this.query);

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _rich(
        context,
        text,
        query,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}

class _HeadingView extends StatelessWidget {
  const _HeadingView(this.text, this.query);

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: _rich(
        context,
        text,
        query,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StepsView extends StatelessWidget {
  const _StepsView(this.items, this.query);

  final List<({String where, String what})> items;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: scheme.primary,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            ..._spans(
                              context,
                              items[i].where,
                              query,
                              style: body?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            ..._spans(
                              context,
                              ' — ${items[i].what}',
                              query,
                              style: body,
                            ),
                          ],
                        ),
                        style: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BulletsView extends StatelessWidget {
  const _BulletsView(this.items, this.query);

  final List<({String term, String text})> items;
  final String query;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 10),
                    child: Text('•', style: body),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (item.term.isNotEmpty)
                            ..._spans(
                              context,
                              item.term,
                              query,
                              style: body?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ..._spans(
                            context,
                            item.term.isEmpty ? item.text : ' ${item.text}',
                            query,
                            style: body,
                          ),
                        ],
                      ),
                      style: body,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView(this.items, this.query);

  final List<({String bad, String good})> items;
  final String query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyMedium;
    Widget cell(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _rich(context, text, query, style: body),
    );
    final bad = scheme.errorContainer.withValues(alpha: 0.4);
    final good = scheme.primaryContainer.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final sideBySide = box.maxWidth >= 420;
          return Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: sideBySide
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cell('✗ ${item.bad}', bad)),
                              const SizedBox(width: 6),
                              Expanded(child: cell('✓ ${item.good}', good)),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            cell('✗ ${item.bad}', bad),
                            const SizedBox(height: 4),
                            cell('✓ ${item.good}', good),
                          ],
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CalloutView extends StatelessWidget {
  const _CalloutView(this.text, this.query, {required this.warn});

  final String text;
  final String query;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = warn ? scheme.errorContainer : scheme.primaryContainer;
    final foreground = warn
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warn ? Icons.warning_amber : Icons.lightbulb_outline,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _rich(
              context,
              text,
              query,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoView extends StatelessWidget {
  const _GoView(this.label, this.target);

  final String label;
  final HelpTarget target;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: () => _HelpScope.of(context).go(context, target),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

class _SourcesView extends StatelessWidget {
  const _SourcesView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final source in helpSources())
            InkWell(
              onTap: () => launchUrl(
                Uri.parse(source.url),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 8),
                      child: Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        source.title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Путь внедрения
// ---------------------------------------------------------------------------

class _PathView extends StatefulWidget {
  const _PathView(this.query);

  final String query;

  @override
  State<_PathView> createState() => _PathViewState();
}

class _PathViewState extends State<_PathView> {
  /// Этапы, у которых пользователь перевернул вид по умолчанию.
  final _flipped = <int>{};

  @override
  Widget build(BuildContext context) {
    final scope = _HelpScope.of(context);
    final stages = scope.stages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NextStep(scope: scope),
        const SizedBox(height: 12),
        for (var i = 0; i < stages.length; i++)
          _StageView(
            key: ValueKey('help-stage-$i'),
            index: i,
            stage: stages[i],
            scope: scope,
            query: widget.query,
            last: i == stages.length - 1,
            // Пройденные этапы свёрнуты, текущий и будущие развёрнуты.
            expanded: (i >= scope.stage) != _flipped.contains(i),
            onToggle: () => setState(() {
              if (!_flipped.remove(i)) _flipped.add(i);
            }),
          ),
      ],
    );
  }
}

/// Плашка «Следующий шаг» со ссылкой на место.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.scope});

  final _HelpScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    HelpStep? next;
    if (scope.stage < scope.stages.length) {
      next = scope.stages[scope.stage].steps
          .where(
            (s) =>
                stepRequired(s, windows: scope.windows) &&
                !stepDone(s.id, scope.facts, scope.manual),
          )
          .firstOrNull;
    }
    final progress = next == null ? null : stepProgress(next.id, scope.facts);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSecondaryContainer,
    );
    return Container(
      key: const ValueKey('help-next-step'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              next == null
                  ? S.helpPathComplete
                  : '${S.helpNextStep(next.title)}'
                        '${progress == null ? '' : ' — $progress'}',
              style: style,
            ),
          ),
          if (next?.target case final target?) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => scope.go(context, target),
              child: Text(S.helpOpen),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageView extends StatelessWidget {
  const _StageView({
    super.key,
    required this.index,
    required this.stage,
    required this.scope,
    required this.query,
    required this.last,
    required this.expanded,
    required this.onToggle,
  });

  final int index;
  final HelpStage stage;
  final _HelpScope scope;
  final String query;
  final bool last;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = scope.visibleSteps(stage);
    final done = stageDone(
      stage,
      scope.facts,
      scope.manual,
      windows: scope.windows,
    );
    final count = steps
        .where((s) => stepDone(s.id, scope.facts, scope.manual))
        .length;
    final body = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final content = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: done ? scheme.primary : null,
                  foregroundColor: done ? scheme.onPrimary : null,
                  child: done
                      ? const Icon(Icons.check, size: 16)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: _rich(
                              context,
                              stage.title,
                              query,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            S.helpStageCount(count, steps.length),
                            style: body,
                          ),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (expanded) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _rich(context, stage.hint, query, style: body),
                    ),
                    for (final step in steps)
                      _StepRow(step: step, scope: scope, query: query),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // Будущие этапы видны, но приглушены.
    return index > scope.stage ? Opacity(opacity: 0.55, child: content) : content;
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.scope, required this.query});

  final HelpStep step;
  final _HelpScope scope;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = stepDone(step.id, scope.facts, scope.manual);
    final manual = manualSteps.contains(step.id);
    final progress = stepProgress(step.id, scope.facts);
    final where = [
      if (step.where != '—') step.where,
      ?progress,
    ].join(' · ');
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final Widget leading = manual
        ? SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              key: ValueKey('help-check-${step.id}'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: done,
              onChanged: (_) => scope.toggleCheck(step.id),
            ),
          )
        : Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            key: ValueKey('help-step-${step.id}'),
            size: 22,
            color: done ? scheme.primary : scheme.onSurfaceVariant,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SizedBox(width: 24, child: Center(child: leading)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _rich(
                      context,
                      step.title,
                      query,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (step.optional)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          S.helpOptional,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                if (where.isNotEmpty) _rich(context, where, query, style: small),
              ],
            ),
          ),
          if (step.target case final target?)
            TextButton(
              onPressed: () => scope.go(context, target),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: Text(S.helpOpen),
            ),
        ],
      ),
    );
  }
}
