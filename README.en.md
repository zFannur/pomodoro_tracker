<div align="center">

<img src="assets/icon/logo.png" width="120" alt="Pomodoro Tracker">

# Pomodoro Tracker

**A Pomodoro timer and task manager for Windows and Android that plays well with Obsidian.**

A Pomodoro-technique timer with a precise model of series, idle time and
focus, a task screen with collapsible groups — plus a personal focus system
(frog of the day, sprint tasks, Flowtime). Tasks, pomodoro history and sprints
sync across devices through your own Google Drive and are mirrored into an
Obsidian vault as plain `.md` files for reading, search and git.

[Русский README](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-E2574C.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-0078D6?logo=windows&logoColor=white)](#quick-start)
[![Storage](https://img.shields.io/badge/Storage-Markdown-3FA45B?logo=markdown&logoColor=white)](#data-storage)
[![Tests](https://img.shields.io/badge/tests-82%20passing-3FA45B.svg)](#tests)

<img src="docs/screenshot-timer.png" width="820" alt="Timer screen">

</div>

No service accounts, no telemetry, no third-party servers: the only cloud is
your own Google Drive, and only if you connect it yourself. Without sync the
app is fully local.

## Why

Ordinary timers keep their history in someone else's database. Here it stays
with you: the working file lives in the app folder, and its readable mirror is
markdown in your own vault — visible in Obsidian's graph, searchable, and easy
to keep in git. Sync goes through your personal Drive, not through a
middleman service.

---

## Contents

- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Screens](#screens)
- [Focus system](#focus-system)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Smart task input](#smart-task-input)
- [Data storage](#data-storage)
- [Google Drive sync](#google-drive-sync)
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

flutter build apk --release
# → build\app\outputs\flutter-apk\app-release.apk
```

On first launch the app creates a storage folder (`…\Obsidian\Помодоро` by
default) — the path can be changed in Settings.

Cross-device sync is optional: without it the app runs fully offline. See
[below](#google-drive-sync) for how to turn it on.

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

### Tasks

A full-screen task manager over the same list the timer uses:

- **Quick-add on top**: smart input, `Enter` — straight to Inbox (capture
  without deciding), `Ctrl+Enter` — to Today, `Ctrl+N` — jump here from
  anywhere in the app;
- **Collapsible groups** with counters and 🍅 totals: Today / Inbox /
  Tomorrow / This week / Later / Done this week (collapse state is
  remembered);
- the first Today task is highlighted as **NOW** (WIP = 1);
- priority = tap 🐸 / tap ⭐ / drag (reordering works inside Planner buckets
  too);
- deleting shows an Undo snackbar;
- wide window (≥1000px) — two columns, narrow — one.

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
| `Ctrl+N` | Tasks screen with the cursor in the quick-add field — from anywhere |

On the Tasks screen: `Enter` — to Inbox, `Ctrl+Enter` — to Today.
Click the pomodoro count: `+1`, `Alt`-click `−1`, `Shift` — ×4.
Shortcuts are disabled while a dialog is open or a text field is focused
(except `Ctrl+N`).

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

**The source of truth is `data.json`** (on Windows
`%APPDATA%\com.local\pomodoro_tracker\`, on Android the app-private directory;
atomic writes, stable ids on every task and every pomodoro). One document for
everything: tasks, journal, sprints and tombstones of deleted records. That
same document is what syncs — so a closed task and the pomodoro it produced
always reach the other device together.

On first launch data is migrated automatically from whatever was there before:
tasks from `tasks.json`, journal and sprints from the vault's markdown. The
source files are not deleted — deleting `data.json` rolls everything back.

Markdown in the storage folder (`…\Obsidian\Помодоро` by default) is a set of
**read-only mirrors**:

```
Помодоро/
├── Задачи.md                    # MIRROR of the task list
├── Входящие.md                  # inbox: capture tasks from Obsidian
├── Журнал/
│   └── 2026-07/
│       └── 2026-07-16.md        # MIRROR: day's pomodoros + notes
└── Спринты/
    └── 2026-W29.md              # MIRROR: milestone, goal, daily facts
```

The folder and file names are fixed (`Задачи.md`, `Журнал/`, `Спринты/`) —
they don't change with the interface language, so your vault stays
consistent no matter which language you use day to day. The **UI language
switch only translates the app's own text**; the markdown format itself
(section headers, table columns) is fixed, and task/category names stay
exactly as you typed them.

### Mirrors are read-only

`Задачи.md`, `Журнал/*.md` and `Спринты/*.md` are regenerated on every change:
visible in Obsidian, searchable, versioned by git, and they double as a
human-readable emergency backup. **Edits to them are not read back and get
overwritten** (a note at the top says so). Edit the weekly milestone in the
app. Mirrors can be turned off in Settings.

`Входящие.md` is the only file read back.

```markdown
<!-- Зеркало Помодоро Трекера: правки здесь не читаются. -->
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

### Входящие.md ("Inbox.md") — capture from Obsidian

Write lines in any shape (`- buy a domain ~1 #misc`, checkboxes and list
markers welcome) — on startup and on window focus the app pulls them into
Inbox through the smart-input parser and resets the file to its template.
Strictly one direction (file → app), so there's nothing to merge. This is
how you add tasks from Obsidian or from your phone (the file syncs via
Google Drive).

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

Daily facts are not stored in `data.json` — they're derived from the journal.
That's why pomodoros don't push the sprint to Drive: the file only travels
when the goal, the milestone or the "done" list actually changes.

### App settings

JSON, **not** in the vault: `%APPDATA%\com.local\pomodoro_tracker\settings.json`
(the folder name comes from `CompanyName` in `windows/runner/Runner.rc` — don't
change it, or the data ends up in a different directory).
Settings are local to the device and never synced — the OAuth keys live there.
`data.json` (all data) and `timer_state.json` (timer state used for restore)
sit next to it.

---

## Google Drive sync

All of `data.json` — tasks, journal and sprints — syncs across devices through
the **hidden app folder** (appDataFolder) on your Google Drive: the file is
invisible both in the Drive UI and to other apps. Settings stay local to each
device.

**How it works:**

- auto-sync on startup, on returning to the window/app (at most once a
  minute) and 5 seconds after any edit;
- the file is compared by its Drive revision: only the remote changed —
  pull; only we changed — push;
- a **conflict** (both devices changed) is resolved by **merging, not by
  picking a winner**: lists are unioned by id, so no task and no pomodoro is
  lost. The newer side only decides contested scalars — the daily goal and the
  weekly milestone. The losing version is additionally saved next door as
  `data_conflict.json`;
- **first connection** of a device to a non-empty Drive uses the same merge:
  nothing gets overwritten on either side.

### Deletions and tombstones

A "shorter file" is indistinguishable from "data hasn't arrived yet", so
deletions are recorded explicitly. On every write the repository diffs the set
of ids before and after: whatever disappeared becomes a tombstone with a
timestamp and travels with the data. Merging subtracts buried ids from every
list.

- deletion wins **unconditionally**: if a record was deleted on one device and
  edited on another, it stays deleted. Device clocks never decide a record's
  fate — clock drift between Android and Windows would bring back
  non-determinism;
- tombstones are produced by diffing at write time rather than at each deletion
  site, which covers every path at once — "minus" to zero, "Clear list",
  deleting a journal entry, merging tasks;
- restoring a record (from the trash) removes its tombstone;
- tombstones older than 90 days are pruned: by then the deletion has reached
  every device.

### Google Cloud setup (one-time)

1. [console.cloud.google.com](https://console.cloud.google.com) → create a
   project (any name).
2. **APIs & Services → Library** → enable the **Google Drive API**.
3. **APIs & Services → OAuth consent screen** → External → fill in the name
   and email → add yourself under **Test users** (no need to publish).
4. **Credentials → Create credentials → OAuth client ID:**
   - **Desktop app** — for Windows. Paste the Client ID + Client Secret into
     Settings → App → Google Drive → "Connect";
   - additionally for Android:
     - **Android** — package `com.zfannur.pomodoro_tracker` + the SHA-1 of the
       key the APK is actually signed with (`cd android && ./gradlew
       signingReport`, the `Variant: release` line). This client's values are
       never entered into the app — it exists so Google can recognise it;
     - **Web application** — paste its Client ID into the
       "Server Client ID (Web)" field in the app settings on the phone.

All three clients must live **in one project** with the Drive API enabled.

The only scope is `drive.appdata` — the app cannot see the rest of your
Drive. Per Google's policy the Desktop client secret is not treated as a
secret for installed apps; it is stored in your local `settings.json`.

**If sign-in fails with `DEVELOPER_ERROR`**, Google found no client matching
the app: usually the Android client holds the SHA-1 of a different key (debug
instead of release), or the clients are spread across separate projects.

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
- storage folder and **mirroring tasks into the vault** (`Задачи.md`);
- categories and **scheme-per-category binding** (a task in that category
  gets that scheme's pomodoro length when estimated). A new category can be
  typed right in the task edit dialog — it registers instantly and shows up
  in every dropdown;
- **Google Drive** — task sync connection
  (see [the section above](#google-drive-sync)).

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
- **Single instance per system**: a second launch raises the existing window
  and exits (two processes would silently overwrite each other's data).

---

## Architecture

Flutter 3.44 / Dart 3.12, Windows desktop + Android. Layers:

```
lib/
├── app/            # strings.dart (all text, ru/en), theme.dart (all colors)
├── core/           # failure.dart
├── domain/
│   ├── entities/   # PomoTask, PomoSession, DayLog, Sprint, AppSettings
│   └── repositories.dart
├── data/
│   ├── markdown_codec.dart       # pure serialize/parse (test-covered)
│   ├── data_merge.dart           # merging two data.json snapshots (pure)
│   ├── json_data_repository.dart # data.json: truth, migration, tombstones, mirrors
│   ├── vault_repositories.dart   # vault access, inbox, settings
│   └── timer_state_store.dart
├── presentation/
│   ├── cubits/     # timer, tasks, journal, sprint, stats, settings, sync
│   ├── screens/    # timer, tasks, sprint, stats, planner_dialog, settings_dialog
│   ├── widgets/    # common.dart
│   └── home_shell.dart
├── services/       # sound_service (WAV-synthesized sounds), notify_service,
│                   # sync_auth (per-platform OAuth), drive_sync_service
└── main.dart       # dependency wiring, 🐸/⭐ rollover
```

- **State**: Cubit (`flutter_bloc`), states are `Equatable`.
- **Errors**: `Either<Failure, T>` (`fpdart`) at the repository boundary.
- **Colors** live only in `theme.dart`, **text** only in `strings.dart`.
- **File writes are atomic** (temp + rename) so Obsidian/Drive never see a
  half-written file. The repository and the sync use **different** temp names:
  a shared one already caused spliced content and broken JSON.
- **`JsonDataRepository` implements three interfaces at once** (tasks, journal,
  sprints): they read one document, so the in-memory state must be one. Hence
  `saveTasks`/`saveSprint` instead of a single `save`.
- **Merging is a pure function with no IO** — the nastiest part of syncing is
  covered by tests instead of by hand on two devices.
- **The repository writes what arrives from Drive** (`applyRemote`), not the
  sync service: otherwise the in-memory document would drift from disk and the
  next write would tombstone everything that had just arrived.

---

## Development

```bash
flutter pub get
flutter analyze          # should be clean
flutter test             # 82 tests
flutter run -d windows   # debug
flutter build windows --release
flutter build apk --release
```

### Android

The signing key is configured in `android/key.properties` (not in git). The
fingerprint of that exact key is registered in Google Cloud — **changing the
key breaks Google sign-in**:

```bash
cd android && ./gradlew signingReport   # SHA-1 for the Cloud Console
```

### App icon

```bash
# assets/icon/logo.png (square, transparent background, some padding)
python tool/make_icon.py     # → Windows .ico + mipmap-*/ic_launcher.png
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
- `test/json_data_repository_test.dart` — migration of tasks and journal,
  round-trip, deterministic ids on migration, tombstones, synthesized empty
  days, mirrors, the inbox file, `applyRemote`.
- `test/data_merge_test.dart` — merging: union by id, delete-wins in both
  directions, survival of unknown sections, idempotence.
- `test/tasks_cubit_planner_test.dart` — bucket reordering, editing, the
  trash, serialized disk writes.
- `test/drive_sync_test.dart` — the Drive sync algorithm: push/pull, merge on
  first connect and on conflict, dirty-flag survival, sign-in called exactly
  once.
- `test/sync_auth_test.dart` — decisions made before Google sign-in is
  initialized (it can't be initialized twice per launch).
- `test/stats_screen_test.dart` — the stats screen lays out at phone and wide
  widths (a layout mistake once broke the whole screen).

---

## Known limitations

- **Markdown files are mirrors only**: edits to `Задачи.md`, `Журнал/*.md` and
  `Спринты/*.md` are never read back and get overwritten on the next write.
  Add tasks from Obsidian via `Входящие.md`; do everything else in the app.
- **Flowtime overtime doesn't survive a restart** — closing the app during
  overtime loses that pomodoro.
- **Android**: no notifications, and the timer only runs while the app is open
  (no background service, deliberately). The storage folder is fixed — picking
  a directory would yield a `content://` URI rather than a path.
- **Day notes and "Done this week" merge by text**, not by id: two literally
  identical lines added on different devices collapse into one. They have no
  delete action in the UI, so giving them ids wasn't worth it.
- **`data.json` grows** — roughly a third of a megabyte per year at ten
  pomodoros a day, and it's uploaded whole on every sync. When that starts to
  hurt, the cheap ways out are compression or moving old years into a separate
  unsynced file. Sharding now would be a bet on a future that may not arrive.
- **Changing the Android signing key breaks Google sign-in**: the Cloud
  Console has the fingerprint of one specific key.
- Deliberately without server-side features: accounts, leaderboards,
  sharing, integrations (Slack/Trello/Todoist, apart from the Google Drive
  sync), email reports, recurring tasks — this is a focused local tool, not
  a SaaS platform.

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
