<div align="center">

<img src="assets/icon/logo.png" width="120" alt="Pomodoro Tracker">

# Pomodoro Tracker

**A desktop Pomodoro timer for Windows that stores everything as markdown.**

A Pomodoro-technique timer with a precise model of series, idle time and
focus — plus a personal focus system (frog of the day, sprint tasks,
Flowtime) and all data as plain `.md` files inside an Obsidian vault.

[Русский README](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-E2574C.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)](#quick-start)
[![Storage](https://img.shields.io/badge/Storage-Markdown-3FA45B?logo=markdown&logoColor=white)](#data-storage)
[![Tests](https://img.shields.io/badge/tests-27%20passing-3FA45B.svg)](#tests)

<img src="docs/screenshot-timer.png" width="820" alt="Timer screen">

</div>

No cloud, no accounts, no telemetry. Data is plain `.md` files you can read
and edit by hand in Obsidian.

## Why

Ordinary timers keep their history in someone else's database. Here,
pomodoros, tasks and sprints are markdown files in your own vault: they show
up in Obsidian's graph, they're searchable, editable by hand, and you can put
them in git. The app is just a convenient interface on top of those files.

---

## Contents

- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Screens](#screens)
- [Focus system](#focus-system)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Smart task input](#smart-task-input)
- [Data storage](#data-storage)
- [Settings](#settings)
- [Exact behavior rules](#exact-behavior-rules)
- [Architecture](#architecture)
- [Development](#development)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Quick start

```bash
flutter pub get
flutter build windows --release
# → build\windows\x64\runner\Release\pomodoro_tracker.exe
```

On first launch the app creates a storage folder (`…\Obsidian\Помодоро` by
default) — the path can be changed in Settings.

---

## Core concepts

| Concept | What it means |
|---|---|
| **Pomodoro** | A work interval (25 min by default). A completed pomodoro is written to the day's journal. |
| **Series** | A running count of consecutive pomodoros. Every N pomodoros triggers a long break. Burns out after a long idle stretch. |
| **Task estimate** | Stored **in minutes**, not checkboxes. Pomodoros = `ceil(minutes / pomodoro length)`. |
| **Current task** | Always the **top** item in "Planned". Also shown in the "NOW" card. |
| **Logical day** | Runs **05:00 to 05:00**. A pomodoro at 00:30 lands in yesterday's file. |
| **Idle time (delay)** | Time while the timer is stopped or paused. Accumulates and lands on the next pomodoro record. |
| **Interruption** | Pausing a running pomodoro. Penalizes focus. |
| **Sprint** | A calendar week (Mon–Sun) with a milestone and a pomodoro goal. |

---

## Screens

### Timer

A single-page flow:

1. **Timer** — large digits, a progress bar, color-coded by phase (work —
   tomato, break — green). The header shows the pomodoro number, the series
   `(N)`, and interruption tick marks `′′`.
2. **NOW** — a card for the current task (WIP = 1).
3. **Planned** — the task list with estimates, a finish-time forecast, and
   category counters.
4. **Done** — today's pomodoro journal with focus, idle time and
   interruptions.

The window title shows `MM:SS category` while running — visible from the
taskbar.

### Sprint

The weekly milestone, ⭐ sprint tasks, "Done this week", fact tiles (Actual /
Time / Velocity / Forecast), progress toward the goal, a daily chart, and
week history.

### Stats

Periods: Today / Week / Month / 365 days / Range.
Tiles: Pomodoros, Time, Focus, 🐸 Frogs, Best day.
Charts: by category, last 14 days, an activity heatmap (from 90 days).

> There's **deliberately** no "day streak" tile — a broken streak feeds
> self-criticism.

---

## Focus system

On top of the classic timer, a personal focus system:

| Element | How it works |
|---|---|
| 🐸 **Frog of the day** | One per day, always at the top of the list. Set from the Planner. **Resets every morning** (05:00 boundary). |
| ⭐ **Sprint task** | A weekly commitment that moves the milestone. Set from the Planner. **Cleared automatically at the start of a new week.** A closed ⭐ task moves to "Done this week". |
| **NOW (WIP = 1)** | One task in progress — the top of the list. |
| **Flowtime** | The pomodoro finishes — the timer quietly keeps counting up (`+ MM:SS`) until you press "Done". Doesn't break your flow. Toggled in Settings. |
| **"Where did you leave off?"** | Stopping a running pomodoro asks a one-line question. The answer goes into the day journal's `## Notes`. Skippable. |
| **Stuck hint** | Idle > 10 min → "Break it down to a 5-minute step — and start." |
| **Overload warning** | More than 3 tasks in a day → a reminder about "🐸 + 2 tasks". |
| **Frog stat** | "🐸 N / M" — days with a frog out of **active** days. No streak. |

**Buckets ≠ sprint.** The Planner (Inbox / Tomorrow / This week / Later) is
about **due dates**. The sprint is only ⭐. A task can be in Inbox and in the
sprint at the same time.

**Category = project.** There's deliberately no separate subtask hierarchy:
big goals live in Obsidian (your own planning notes), this app is about
execution. Group a project's tasks under one category and watch its counter.

---

## Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Start / Pause |
| `Esc` `Esc` | Stop (or Skip break) — **double press**, second one within 1.5s. The button turns red while armed. |
| `+` / `−` | Pomodoros of the first task (`Shift` — by 4) |

Click the pomodoro count: `+1`, `Alt`-click `−1`, `Shift` — ×4.
Shortcuts are disabled while a dialog is open or a text field is focused.

---

## Smart task input

In the description field:

```
#category Task description ~3
```

- `#category` — at the start of the line, sets the category;
- `~N` or `::N` — number of pomodoros (capped at 300 minutes);
- without them, the category from the dropdown and the active scheme's
  pomodoro length are used.

The **📥** button captures straight to "Inbox" — bypassing today's list.

---

## Data storage

Everything lives in the storage folder (`…\Obsidian\Помодоро` by default):

```
Помодоро/
├── Задачи.md                    # Today + Planner
├── Журнал/
│   └── 2026-07/
│       └── 2026-07-16.md        # day's pomodoros + notes
└── Спринты/
    └── 2026-W29.md              # milestone, goal, daily facts
```

The folder and file names are fixed (`Задачи.md`, `Журнал/`, `Спринты/`) —
they don't change with the interface language, so your vault stays
consistent no matter which language you use day to day. The **UI language
switch only translates the app's own text**; the markdown format itself
(section headers, table columns) is fixed, and task/category names stay
exactly as you typed them.

### Задачи.md ("Tasks.md")

```markdown
# Задачи

## Сегодня
- 🐸 Сделать оплату #проекты ⏱ 50м ⭐
- Код-ревью PR 42 #работа ⏱ 25м

## Планировщик
- Посмотреть пример держателя #работа ⏱ 30м 📅 2026-07-18
```

- `🐸` — frog-of-the-day prefix; `⭐` — sprint-task suffix;
- `⏱ 50м` — estimate in minutes; `📅 2026-07-18` — due date (the Planner tab
  is computed from the date, and **overdue items automatically show up in
  "Inbox"**).

### Журнал/YYYY-MM/YYYY-MM-DD.md ("Journal")

```markdown
---
дата: 2026-07-16
помидоры: 3
минуты: 75
простой: 7
прерывания: 2
фокус: 92%
цель: 8
---

# 16.07.2026 · 3 🍅 · 1ч 15м · фокус 92%

| Начало | Мин | Простой | Прерывания | Категория | Задача | Как |
| ------ | --- | ------- | ---------- | --------- | ------ | --- |
| 09:12 | 25 | 0 | 0 | работа | 🐸 Код-ревью | таймер |
| 10:05 | 25 | 7 | 2 | личное | Английский | вручную |

## Заметки
- 14:30 — встал на верстке карточки, не сходится отступ
```

- `🐸` on a task row = a pomodoro completed while it was the frog (used for
  the frog stat);
- `таймер` / `вручную` — logged by the running timer or entered manually;
- hours `00:00–04:59` belong to the next calendar date (logical day).

### Спринты/YYYY-Wnn.md ("Sprints")

Frontmatter (goal, milestone, week bounds, weekly facts), a `## Задачи
недели` snapshot, `## Сделано за неделю`, and a `## По дням` table.

Hand-edited and survive being overwritten: the **goal**, the **milestone**,
and **"Done this week"**.

### App settings

JSON, **not** in the vault: `%APPDATA%\com.local\pomodoro_tracker\settings.json`.
`timer_state.json` lives next to it — the timer state used for restore.

---

## Settings

### Timer

- **Schemes** (up to 6): `classic` 25/5/15×4, `work` 50/10/20×2, `personal`
  30/2/25×4 — durations are editable, schemes can be added;
- auto-start pomodoro after a break / break after a pomodoro / only if tasks
  are queued;
- **Flowtime**;
- daily goal (0 — none), default sprint goal (40).

### Notifications

- volume, finish sound (10 melodies: bell, beep, chime, cuckoo, guitar,
  maramba, organ, rise, satellite, school), ticking (optional, including
  during breaks);
- system notifications, a one-minute warning, raising the window;
- **custom notification texts** — one per line, a random one is picked;
- **Telegram** — mirror notifications through your own bot (token + chat id).

### App

- theme: Light / Dark / System / **Auto** (light 07:00–18:59) / **Matrix**
  (black background, neon green, monospace font);
- **interface language** — Russian / English, switches instantly, no restart
  needed;
- date format (6 options) and time format (24h / 12h);
- storage folder;
- categories and **scheme-per-category binding** (a task in that category
  gets that scheme's pomodoro length when estimated).

Category names and the markdown files themselves always stay in whatever
language you typed them in — the interface language only affects the app's
own text, not your data.

---

## Exact behavior rules

The key rules that define timer and journal behavior:

- **Focus** = `0` for an empty day; otherwise `base = 1 − idle / (2 ×
  minutes)` (`0.5` when minutes is zero); with interruptions,
  `base = min(base, 0.99) ^ ((pomodoros + interruptions) / pomodoros)`;
  result clamped to 0..100.
- **Idle time** accumulates while the timer is stopped/paused and lands on
  the **next** record, capped at the pomodoro length. The **first record of
  the day** always has idle time `0`.
- **The series burns out** if the idle time before a start is longer than a
  long break. A long break also resets the series.
- **Anti-cheat**: a timer-sourced record can't be longer than the minutes
  that actually elapsed since the previous one.
- **Finish-time forecast** accounts for breaks and picks break type from the
  running series counter.
- **Restore**: timer state survives a restart if **less than 1 hour** has
  passed.
- **Day rollover** is caught live (checked once a minute): the "Done" list
  starts over, 🐸 resets, and ⭐ clears on a week change.

---

## Architecture

Flutter 3.44 / Dart 3.12, Windows desktop. Layers:

```
lib/
├── app/            # strings.dart (all text, ru/en), theme.dart (all colors)
├── core/           # failure.dart
├── domain/
│   ├── entities/   # PomoTask, PomoSession, DayLog, Sprint, AppSettings
│   └── repositories.dart
├── data/
│   ├── markdown_codec.dart      # pure serialize/parse (test-covered)
│   ├── vault_repositories.dart  # file access, atomic writes
│   └── timer_state_store.dart
├── presentation/
│   ├── cubits/     # timer, tasks, journal, sprint, stats, settings
│   ├── screens/    # timer, sprint, stats, planner_dialog, settings_dialog
│   ├── widgets/    # common.dart
│   └── home_shell.dart
├── services/       # sound_service (WAV-synthesized sounds), notify_service
└── main.dart       # dependency wiring, 🐸/⭐ rollover
```

- **State**: Cubit (`flutter_bloc`), states are `Equatable`.
- **Errors**: `Either<Failure, T>` (`fpdart`) at the repository boundary.
- **Colors** live only in `theme.dart`, **text** only in `strings.dart`.
- **File writes are atomic** (temp + rename) so Obsidian/Drive never see a
  half-written file.

---

## Development

```bash
flutter pub get
flutter analyze          # should be clean
flutter test             # 27 tests
flutter run -d windows   # debug
flutter build windows --release
```

### App icon

```bash
# assets/icon/logo.png (square, transparent background, some padding)
python tool/make_icon.py     # → windows/runner/resources/app_icon.ico (16..256)
flutter build windows --release
```

A multi-resolution `.ico` is required: with a single 256px entry, Windows
crudely downscales it to 24px in the taskbar. After changing the icon you
may need to clear the Windows icon cache (`IconCache.db` + restart Explorer).

### Tests

- `test/markdown_codec_test.dart` — round-trip of tasks, journal (🐸, `|`,
  overnight pomodoros), sprint; the focus formula; logical date; ISO weeks.
- `test/timer_cubit_test.dart` — pomodoro/break cycle, series, pause and
  interruptions, stop, skip, prolong, smart input.
- `test/stats_frog_test.dart` — counting days with a frog.
- `test/strings_test.dart` — interface language switching, localized time
  units.

---

## Known limitations

- **External edits to `Задачи.md` while the app is open get overwritten** —
  the file is only read at startup, there's no file watcher. Edit it while
  the app is closed.
- **Flowtime overtime doesn't survive a restart** — closing the app during
  overtime loses that pomodoro.
- In the sprint file, only "its own" sections survive an overwrite (goal,
  milestone, "Done this week"); any sections you add by hand will be erased.
- Deliberately without server-side features: accounts, leaderboards,
  sharing, integrations (Slack/Trello/Todoist/Google), email reports,
  recurring tasks — this is a focused local tool, not a SaaS platform.

---

## Contributing

This is a personal project, but PRs and issues are welcome.

Before a PR:

```bash
flutter analyze   # should be clean
flutter test      # all green
dart format lib test
```

Codebase rules:

- **colors** only in `lib/app/theme.dart`, **text** only in
  `lib/app/strings.dart`;
- repositories return `Either<Failure, T>`, the `domain` / `data` /
  `presentation` layers stay separate;
- markdown parsing logic lives in `markdown_codec.dart` (pure functions) and
  is test-covered;
- any timers are cancelled in `close()` / `dispose()`;
- deliberate simplifications are marked with a `// ponytail:` comment
  naming the ceiling of the shortcut.

Changes to core behavior rules (the focus formula, idle time, series, the
logical day) need a test.

## License

[MIT](LICENSE) © zFannur

"Pomodoro Technique" is a trademark of Francesco Cirillo; this project is
not affiliated with, and is not an official implementation of, the
technique.
