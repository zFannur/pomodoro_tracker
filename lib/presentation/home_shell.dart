import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../app/strings.dart';
import 'cubits/settings_cubit.dart';
import 'cubits/tasks_cubit.dart';
import 'cubits/timer_cubit.dart';
import 'screens/settings_dialog.dart';
import 'screens/sprint_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/timer_screen.dart';

/// Оболочка: NavigationRail + горячие клавиши + заголовок окна с отсчётом.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Не перехватываем клавиши, когда открыт диалог/меню: иначе Esc в диалоге
    // одновременно закрывал его и стопал помидор, а Space дёргал таймер.
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // Не перехватываем клавиши, когда фокус в текстовом поле.
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    if (focused is EditableText) return false;
    final timer = context.read<TimerCubit>();
    final tasks = context.read<TasksCubit>();
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      timer.spacePressed();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      timer.escPressed();
      return true;
    }
    // +/− меняют помидоры первой задачи (Shift — по 4).
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      if (tasks.state.todo.isNotEmpty) {
        tasks.plus(0, count: shift ? 4 : 1);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      if (tasks.state.todo.isNotEmpty) {
        tasks.minus(0, count: shift ? 4 : 1);
      }
      return true;
    }
    return false;
  }

  /// Иконка раздела: активная — в полную силу, неактивная — приглушена.
  Widget _navIcon(String asset, {required bool selected}) {
    return Opacity(
      opacity: selected ? 1 : 0.45,
      child: Image.asset(asset, width: 30, height: 30),
    );
  }

  /// Заголовок окна: при работающем таймере — «MM:SS контекст».
  void _updateTitle(TimerState timer) {
    if (!timer.running) {
      windowManager.setTitle(S.appTitle);
      return;
    }
    final m = (timer.remaining ~/ 60).toString().padLeft(2, '0');
    final s = (timer.remaining % 60).toString().padLeft(2, '0');
    String context_;
    if (timer.mode == TimerMode.pomodoro) {
      final current = context.read<TasksCubit>().state.current;
      context_ = current == null
          ? S.pomodoroWord.toLowerCase()
          : (current.category.isNotEmpty
                ? current.category
                : current.description);
    } else {
      context_ = S.breakWord;
    }
    windowManager.setTitle('$m:$s $context_');
  }

  @override
  Widget build(BuildContext context) {
    // watch, не read: нав-лейблы (S.navTimer и т.п.) не имеют своего
    // BlocBuilder, поэтому смена языка должна перестраивать сам HomeShell.
    final language = context.watch<SettingsCubit>().state.settings.language;
    return BlocListener<TimerCubit, TimerState>(
      listener: (context, timer) => _updateTitle(timer),
      child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Image.asset(
                  'assets/nav/logo.png',
                  width: 34,
                  height: 34,
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      tooltip: S.settings,
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => showSettingsDialog(context),
                    ),
                  ),
                ),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: _navIcon('assets/nav/timer.png', selected: false),
                  selectedIcon: _navIcon(
                    'assets/nav/timer.png',
                    selected: true,
                  ),
                  label: Text(S.navTimer),
                ),
                NavigationRailDestination(
                  icon: _navIcon('assets/nav/sprint.png', selected: false),
                  selectedIcon: _navIcon(
                    'assets/nav/sprint.png',
                    selected: true,
                  ),
                  label: Text(S.navSprint),
                ),
                NavigationRailDestination(
                  icon: _navIcon('assets/nav/stats.png', selected: false),
                  selectedIcon: _navIcon(
                    'assets/nav/stats.png',
                    selected: true,
                  ),
                  label: Text(S.navStats),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // Ключ на языке: экраны без своего context.watch(SettingsCubit)
              // (например StatsScreen) иначе не подхватят смену языка сами.
              child: IndexedStack(
                key: ValueKey(language),
                index: _index,
                sizing: StackFit.expand,
                children: const [TimerScreen(), SprintScreen(), StatsScreen()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
