import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/strings.dart';
import '../../domain/entities/app_settings.dart';
import '../cubits/settings_cubit.dart';

void showSettingsDialog(BuildContext context) {
  // Резолвим кубит сразу, а не внутри builder: тот вызывается лениво, и к
  // тому моменту исходный context мог стать невалидным (например, если
  // экран за диалогом успел перестроиться).
  final cubit = context.read<SettingsCubit>();
  showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(value: cubit, child: const _SettingsDialog()),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.settings,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: S.close,
                    ),
                  ],
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: S.tabTimer),
                  Tab(text: S.tabNotify),
                  Tab(text: S.tabApp),
                ],
              ),
              Expanded(
                child: BlocBuilder<SettingsCubit, SettingsState>(
                  builder: (context, state) {
                    final settings = state.settings;
                    return TabBarView(
                      children: [
                        _TimerTab(settings: settings),
                        _NotifyTab(settings: settings),
                        _AppTab(settings: settings),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _update(BuildContext context, AppSettings next) {
  context.read<SettingsCubit>().update(next);
}

// ---------------------------------------------------------------------------
// Вкладка «Таймер»
// ---------------------------------------------------------------------------

class _TimerTab extends StatelessWidget {
  const _TimerTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = settings.scheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${S.settingsSchemes}:',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [
              ...settings.schemes,
            ]..sort((a, b) => a.name.compareTo(b.name)))
              InputChip(
                label: Text(
                  '${s.name} · ${s.pomodoro} ${s.shortBreak} ${s.longBreak} ${s.longEvery}',
                ),
                selected: s.name == settings.activeScheme,
                onSelected: (_) =>
                    _update(context, settings.copyWith(activeScheme: s.name)),
                onDeleted: settings.schemes.length > 1
                    ? () {
                        final rest = settings.schemes
                            .where((x) => x.name != s.name)
                            .toList(growable: false);
                        _update(
                          context,
                          settings.copyWith(
                            schemes: rest,
                            activeScheme: s.name == settings.activeScheme
                                ? rest.first.name
                                : settings.activeScheme,
                          ),
                        );
                      }
                    : null,
              ),
            if (settings.schemes.length < 6)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(S.addScheme),
                onPressed: () => _addScheme(context),
              ),
          ],
        ),
        const Divider(height: 24),
        _NumberRow(
          label: S.pomodoroLen,
          value: scheme.pomodoro,
          min: 1,
          max: 180,
          onChanged: (v) =>
              _updateScheme(context, scheme.copyWith(pomodoro: v)),
        ),
        _NumberRow(
          label: S.shortLen,
          value: scheme.shortBreak,
          min: 1,
          max: 60,
          onChanged: (v) =>
              _updateScheme(context, scheme.copyWith(shortBreak: v)),
        ),
        _NumberRow(
          label: S.longLen,
          value: scheme.longBreak,
          min: 1,
          max: 120,
          onChanged: (v) =>
              _updateScheme(context, scheme.copyWith(longBreak: v)),
        ),
        _NumberRow(
          label: S.longEvery,
          value: scheme.longEvery,
          min: 1,
          max: 12,
          onChanged: (v) =>
              _updateScheme(context, scheme.copyWith(longEvery: v)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          dense: true,
          title: Text(S.autostartBreak),
          value: settings.autostartBreak,
          onChanged: (v) =>
              _update(context, settings.copyWith(autostartBreak: v)),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.autostartPomodoro),
          value: settings.autostartPomodoro,
          onChanged: (v) =>
              _update(context, settings.copyWith(autostartPomodoro: v)),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.autostartIfTodo),
          value: settings.autostartIfTodo,
          onChanged: settings.autostartPomodoro
              ? (v) => _update(context, settings.copyWith(autostartIfTodo: v))
              : null,
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.flowtimeLabel),
          value: settings.flowtime,
          onChanged: (v) => _update(context, settings.copyWith(flowtime: v)),
        ),
        _NumberRow(
          label: S.dailyGoal,
          value: settings.dailyGoal,
          min: 0,
          max: 32,
          onChanged: (v) => _update(context, settings.copyWith(dailyGoal: v)),
        ),
        _NumberRow(
          label: S.sprintGoalDefault,
          value: settings.sprintGoal,
          min: 1,
          max: 200,
          onChanged: (v) => _update(context, settings.copyWith(sprintGoal: v)),
        ),
      ],
    );
  }

  void _updateScheme(BuildContext context, TimerScheme updated) {
    final schemes = settings.schemes
        .map((s) => s.name == updated.name ? updated : s)
        .toList(growable: false);
    _update(context, settings.copyWith(schemes: schemes));
  }

  void _addScheme(BuildContext context) {
    final controller = TextEditingController();
    showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.addScheme),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 10,
              decoration: InputDecoration(labelText: S.schemeName),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(S.add),
              ),
            ],
          ),
        )
        .then((name) {
          final trimmed = (name ?? '').trim().replaceAll(' ', '-');
          if (trimmed.isEmpty || !context.mounted) return;
          if (settings.schemes.any((s) => s.name == trimmed)) return;
          _update(
            context,
            settings.copyWith(
              schemes: [
                ...settings.schemes,
                settings.scheme.copyWith(name: trimmed),
              ],
              activeScheme: trimmed,
            ),
          );
        })
        .whenComplete(controller.dispose);
  }
}

// ---------------------------------------------------------------------------
// Вкладка «Оповещения»
// ---------------------------------------------------------------------------

class _NotifyTab extends StatelessWidget {
  const _NotifyTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          dense: true,
          title: Text(S.volume),
          subtitle: Slider(
            value: settings.volume,
            onChanged: (v) => _update(context, settings.copyWith(volume: v)),
          ),
          trailing: Text('${(settings.volume * 100).round()}%'),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.finishSound),
          value: settings.finishSoundEnabled,
          onChanged: (v) =>
              _update(context, settings.copyWith(finishSoundEnabled: v)),
        ),
        ListTile(
          dense: true,
          title: Text(S.finishMelody),
          trailing: DropdownMenu<FinishSound>(
            initialSelection: settings.finishSound,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              for (final s in FinishSound.values)
                DropdownMenuEntry(value: s, label: s.name),
            ],
            onSelected: (v) {
              if (v != null) {
                _update(context, settings.copyWith(finishSound: v));
              }
            },
          ),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.tickingSound),
          value: settings.tickingSound,
          onChanged: (v) =>
              _update(context, settings.copyWith(tickingSound: v)),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.tickingInBreaks),
          value: settings.tickingInBreaks,
          onChanged: (v) =>
              _update(context, settings.copyWith(tickingInBreaks: v)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          dense: true,
          title: Text(S.notifications),
          value: settings.notifications,
          onChanged: (v) =>
              _update(context, settings.copyWith(notifications: v)),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.notifyMinuteBefore),
          value: settings.notifyMinuteBefore,
          onChanged: (v) =>
              _update(context, settings.copyWith(notifyMinuteBefore: v)),
        ),
        SwitchListTile(
          dense: true,
          title: Text(S.popupRaiseWindow),
          value: settings.popupRaiseWindow,
          onChanged: (v) =>
              _update(context, settings.copyWith(popupRaiseWindow: v)),
        ),
        const Divider(height: 24),
        Text(S.messages, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        _MessagesField(
          hint: S.msgPomodoroHint,
          value: settings.msgPomodoroDone,
          onChanged: (v) =>
              _update(context, settings.copyWith(msgPomodoroDone: v)),
        ),
        const SizedBox(height: 8),
        _MessagesField(
          hint: S.msgBreakHint,
          value: settings.msgBreakDone,
          onChanged: (v) =>
              _update(context, settings.copyWith(msgBreakDone: v)),
        ),
        const Divider(height: 24),
        Text(S.telegram, style: Theme.of(context).textTheme.labelLarge),
        SwitchListTile(
          dense: true,
          title: Text(S.notifyTelegram),
          value: settings.notifyTelegram,
          onChanged: (v) =>
              _update(context, settings.copyWith(notifyTelegram: v)),
        ),
        _TextRow(
          label: S.telegramToken,
          value: settings.telegramToken,
          obscure: true,
          onChanged: (v) =>
              _update(context, settings.copyWith(telegramToken: v)),
        ),
        _TextRow(
          label: S.telegramChatId,
          value: settings.telegramChatId,
          onChanged: (v) =>
              _update(context, settings.copyWith(telegramChatId: v)),
        ),
      ],
    );
  }
}

class _MessagesField extends StatefulWidget {
  const _MessagesField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_MessagesField> createState() => _MessagesFieldState();
}

// Stateful: контроллер в build терял ввод при любом ребилде настроек
// (слайдер громкости и т.п.) и утекал.
class _MessagesFieldState extends State<_MessagesField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (has) {
        if (!has) widget.onChanged(_controller.text);
      },
      child: TextField(
        controller: _controller,
        maxLines: 3,
        decoration: InputDecoration(
          helperText: widget.hint,
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Вкладка «Приложение»
// ---------------------------------------------------------------------------

class _AppTab extends StatelessWidget {
  const _AppTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.themeMode, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<AppThemeMode>(
                segments: [
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text(S.themeLight),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text(S.themeDark),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text(S.themeSystem),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.auto,
                    label: Text(S.themeAuto),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.matrix,
                    label: Text(S.themeMatrix),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) =>
                    _update(context, settings.copyWith(themeMode: s.first)),
              ),
            ],
          ),
        ),
        ListTile(
          dense: true,
          title: Text(S.language),
          trailing: SegmentedButton<AppLanguage>(
            segments: [
              ButtonSegment(value: AppLanguage.ru, label: Text(S.languageRu)),
              ButtonSegment(value: AppLanguage.en, label: Text(S.languageEn)),
            ],
            selected: {settings.language},
            onSelectionChanged: (s) =>
                _update(context, settings.copyWith(language: s.first)),
          ),
        ),
        ListTile(
          dense: true,
          title: Text(S.dateFormat),
          trailing: DropdownMenu<DateFmt>(
            initialSelection: settings.dateFmt,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              for (final f in DateFmt.values)
                DropdownMenuEntry(value: f, label: f.pattern),
            ],
            onSelected: (v) {
              if (v != null) _update(context, settings.copyWith(dateFmt: v));
            },
          ),
        ),
        ListTile(
          dense: true,
          title: Text(S.timeFormat),
          trailing: SegmentedButton<TimeFmt>(
            segments: const [
              ButtonSegment(value: TimeFmt.h12, label: Text('2:00PM')),
              ButtonSegment(value: TimeFmt.h24, label: Text('14:00')),
            ],
            selected: {settings.timeFmt},
            onSelectionChanged: (s) =>
                _update(context, settings.copyWith(timeFmt: s.first)),
          ),
        ),
        ListTile(
          dense: true,
          title: Text(S.storageFolder),
          subtitle: Text(settings.storagePath),
          trailing: OutlinedButton(
            onPressed: () async {
              final path = await FilePicker.getDirectoryPath(
                initialDirectory: settings.storagePath,
              );
              if (path != null && context.mounted) {
                _update(context, settings.copyWith(storagePath: path));
              }
            },
            child: Text(S.chooseFolder),
          ),
        ),
        const Divider(height: 24),
        Text('${S.categories}:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in settings.categories.entries)
              InputChip(
                label: Text(
                  entry.value == null
                      ? entry.key
                      : '${entry.key} · ${entry.value}',
                ),
                onPressed: () => _bindScheme(context, entry.key),
                onDeleted: settings.categories.length > 1
                    ? () {
                        final next = {...settings.categories}
                          ..remove(entry.key);
                        _update(context, settings.copyWith(categories: next));
                      }
                    : null,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(S.newCategory),
              onPressed: () => _addCategory(context),
            ),
          ],
        ),
      ],
    );
  }

  /// Привязка схемы к категории: новая задача категории получает её
  /// длительность, верхняя задача автоматически применяет схему.
  void _bindScheme(BuildContext context, String category) {
    showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('${S.boundScheme}: $category'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: Text(S.defaultScheme),
          ),
          for (final s in settings.schemes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(s.name),
              child: Text(
                '${s.name} · ${s.pomodoro} ${s.shortBreak} ${s.longBreak} ${s.longEvery}',
              ),
            ),
        ],
      ),
    ).then((choice) {
      if (choice == null || !context.mounted) return;
      final next = {...settings.categories};
      next[category] = choice.isEmpty ? null : choice;
      _update(context, settings.copyWith(categories: next));
    });
  }

  void _addCategory(BuildContext context) {
    final controller = TextEditingController();
    showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.newCategory),
            content: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(S.add),
              ),
            ],
          ),
        )
        .then((name) {
          final trimmed = (name ?? '').trim().replaceAll(' ', '-');
          if (trimmed.isEmpty || !context.mounted) return;
          if (settings.categories.containsKey(trimmed)) return;
          _update(
            context,
            settings.copyWith(
              categories: {...settings.categories, trimmed: null},
            ),
          );
        })
        .whenComplete(controller.dispose);
  }
}

// ---------------------------------------------------------------------------
// Мелкие поля
// ---------------------------------------------------------------------------

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text('$value', textAlign: TextAlign.center),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.obscure = false,
  });

  final String label;
  final String value;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  State<_TextRow> createState() => _TextRowState();
}

// Stateful: контроллер в build терял ввод при любом ребилде настроек и утекал.
class _TextRowState extends State<_TextRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Focus(
        onFocusChange: (has) {
          if (!has) widget.onChanged(_controller.text.trim());
        },
        child: TextField(
          controller: _controller,
          obscureText: widget.obscure,
          decoration: InputDecoration(
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
