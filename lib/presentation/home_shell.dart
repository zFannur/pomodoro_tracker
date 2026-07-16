import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../app/strings.dart';
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
    return BlocListener<TimerCubit, TimerState>(
      listener: (context, timer) => _updateTitle(timer),
      child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 12),
                child: Text('🍅', style: TextStyle(fontSize: 26)),
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
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.timer_outlined),
                  selectedIcon: Icon(Icons.timer),
                  label: Text(S.navTimer),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.flag_outlined),
                  selectedIcon: Icon(Icons.flag),
                  label: Text(S.navSprint),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text(S.navStats),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
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
