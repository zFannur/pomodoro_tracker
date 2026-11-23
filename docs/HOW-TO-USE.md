# How to use

> Generated from the in-app help — edit `lib/app/help_content.dart`, then run `UPDATE_HELP_DOC=1 flutter test test/help_doc_test.dart`.

---

## 🚀 Where to start

> This is more than a timer. There are three layers: planning (what matters), doing (pomodoros) and self-observation (what gets in the way and what helps). Adopt it in stages: a stage is about a week.

A stage is complete when all its required steps are checked; optional ones do not hold it back. In the app the checks appear on their own, from your data; only the "manual" steps are checked by hand.

### Stage 1. Setup

Once, 15 minutes. Without directions and categories the review does not know where your attention goes.

| Step | Where | Checked |
|---|---|---|
| Create 2–3 directions | Course → "Add direction" | auto: active directions ≥ 2 |
| Link categories | Course → ⋮ → Categories | auto: every active direction has ≥ 1 category |
| Write the milestone ladder | Course → card → "Add milestone" | auto: every active direction has ≥ 3 milestones |
| Set session windows *(optional)* | Settings → Timer → Session schedule | auto: the schedule is not empty |
| Flag distracting windows *(Windows)* | Review → Windows → flag | auto: at least one flag exists |
| Connect the AI *(optional)* | Settings → AI | auto: the key is set |

### Stage 2. Observation week

We fix nothing — we only mark. In a week there will be something to compare with.

| Step | Where | Checked |
|---|---|---|
| Rate your sleep in the morning | Timer → Day card | auto: ≥ 3 mornings of the last 7 |
| Answer signals with a cause | Episode sheet | auto: ≥ 5 episodes with a cause in 7 days |
| Keep the "🐸 + 2" day | Tasks | auto: ≥ 3 days with a pomodoro on the 🐸 in 7 days |
| Fix nothing — only mark | — | manual |

### Stage 3. First experiment

One hypothesis a week. Methods from the episode sheet are offered now.

| Step | Where | Checked |
|---|---|---|
| On Monday, read the weekly review | Review → Week | manual |
| Take an experiment | Review → Experiment | auto: the current week has an experiment |
| Try methods from the sheet | Episode sheet → step 2 | auto: ≥ 3 episodes with a method in 7 days |
| Give the 🐸 a first step | Tasks → task → Start plan | auto: a task in "Today" has a first step |

### Stage 4. "If — then" and warm-up

We tie the start to a situation and learn to begin small.

| Step | Where | Checked |
|---|---|---|
| Set an "if — then" for the 🐸 | Tasks → task → Start plan → "When…" | auto: a task in "Today" has a "When" |
| Give last experiment a verdict | Review → Experiment | auto: last week has a verdict |
| Start with a warm-up at least once | Episode sheet → "Just 10 minutes" | auto: an episode with the "Just 10 minutes" method exists |

### Stage 5. Your own rhythm

We keep what worked for you and look once a month.

| Step | Where | Checked |
|---|---|---|
| Take the procrastination scale | Review → Scale | auto: the scale was taken this month |
| Compare with the observation week | Review → tiles, the "base" line | manual |
| Keep what works, drop the rest | Review → Experiment | manual |
| Once a month — review on the Course | Course → banner | manual |

> 💡 Checks appear on their own when the data shows the step is done. You only check by hand what the app cannot see.

---

## 🧭 How it fits together

> Four levels, each 5–10 times bigger than the one below. That is why a direction ends up with 6–12 milestones — a list that fits on screen.

1. **Direction** — 3–12 months. 2–4 active, the rest on pause.
2. **Milestone** — 1–3 weeks. An outcome you can check with a yes or a no.
3. **⭐ Sprint task** — days. The commitment of the week, moves the milestone.
4. **🍅 Pomodoro** — 25 minutes. The unit of work.

### A category is a project

A direction holds a list of categories. Everything done in those categories counts toward it automatically — including past history. You never link tasks to a direction by hand.

### A direction's "Why"

The direction's ⋮ menu has a "Why" item: one line about what will change in your life once the direction is done. It shows on the card and in `Курс.md`, and the "Why this matters to me" approach shows it when a task feels pointless.

### Buckets are deadlines, the sprint is ⭐

Inbox, Tomorrow, This week, Later — when to do it. The sprint is only tasks with ⭐. A task can sit in the Inbox and still be in the sprint.

### "Today"

- **NOW** — the top task of the list. Only one is in progress.
- **🐸 Frog** — the most unpleasant task of the day, goes first. Cleared at 05:00.
- **Days** run from 05:00 to 05:00: a pomodoro at 00:30 is still yesterday.

---

## ☀️ One day

### Morning — 2 minutes

1. **Timer → Day card** — rate your sleep and energy. Two taps.
2. **Tasks** — build "Today": the 🐸 and two more tasks. No more.
3. **Tasks** — put the 🐸 on the most unpleasant one. Open it and fill in "First step" in "Start plan".
4. **Timer** — check the NOW card and press Space.

### Work

- **One task.** The top one is in progress. The others wait.
- **A thought or a new chore** — `Ctrl+N`, `Enter`: it flies into the Inbox and the day stays intact.
- **Not going** — the "Not going" button next to Start, or the "Stuck?" chip. One cause, one method.
- **Do not feel like starting** — a 10-minute warm-up. After it you may honestly stop.
- **Stopped a pomodoro** — "Where did you stop?" in one line. If you stopped because you did not finish, mark the cause.

### Evening — 5 seconds

Day card: "How was your day?". That is all.

> 💡 Manual input is under a minute a day. The app counts delays, postponements and distractions itself.

---

## 📅 Week and month

### Monday — 10 minutes

1. **Review → Week** — look at the tiles and the frequent causes.
2. **Review → Experiment** — give last week a verdict. The automatic verdict can be corrected.
3. **Review → Experiment** — take a new one: the suggested one or your own.
4. **Sprint** — "Take the next step": the milestone of the week is filled in from the ladder.
5. **Tasks** — put ⭐ on 2–3 tasks that move this step.

### When a step is done

Sprint → "Close milestone". The next one fills in by itself, and the closing stays in the Course feed for good. An unfinished step does not burn — on Monday you take it again.

### Once a month — 10 minutes

1. **Course** — the monthly review banner. For every stuck direction: "Pause" or "Make it No. 1".
2. **Review** — the procrastination scale, 9 questions. The card appears in the first week of the month.

---

## 🧱 When it is not going

> Procrastination is not laziness or a character flaw. It is a way to step away for a moment from the unpleasant feeling a task causes. What helps is not "pull yourself together" but understanding the feeling and making the way into the task smaller.

### Signals — the app catches them itself

- **Idle** — the timer has stood for 10 minutes while there are tasks: a "Stuck?" chip appears. On Windows, after 15 minutes, a single notification if you are at the computer.
- **Distraction** — a flagged window stays open for a minute during a pomodoro: a notification and a chip.
- **Postponed** — you put off a task that is already due. From the third time — a ↻3 badge.
- **🐸 untouched** — no pomodoro on the frog all day: the Day card tells you about it in the morning.
- **Early stop** — the cause in the "Where did you stop?" window.
- **You noticed** — the "Not going" button.

Answering is optional. A signal without an answer still goes into the review.

### Episode sheet — three steps

1. **Cause** — one tap. A thought is optional, in one line.
2. **Method** — the one that helped you most is first. Does not fit — "Another method".
3. **Action** — the button saves and starts the timer. The sheet closes.

### Seven causes

- **Not sure where to start** — the task is vague, it has no first action.
- **Too big** — no end in sight, scary to begin.
- **Boring** — no interest and no quick reward.
- **Afraid it won't be good** — perfectionism, fear of judgment.
- **No energy** — it is about your state, not the task.
- **Don't see the point** — the task is not tied to what matters to you.
- **Interrupted** — an outside disturbance. It is not procrastination, but it counts too.

### Nine methods

- **First step in 5 minutes** — when it is unclear or too big. Write down the very first physical action. Not a decision — just the way in.
- **Just 10 minutes** — when it is boring or you have no energy. A 10-minute warm-up, then you may stop. Usually you will not want to.
- **An "if — then" plan** — "When ___, I ___". It works through repetition, which is why the plan is shown in the morning and in NOW.
- **Shrink the task** — the smallest version that still counts as a step forward. Do it first.
- **Check the thought** — a thought is a hypothesis, not a fact. What do you know for sure? How could you put it more accurately?
- **Take the feeling along** — "I notice the thought that…". Do not wait until it stops being scary.
- **Why does this matter to me** — recall the "why" of the direction. If the task is not about your goals, it belongs in the Inbox.
- **An honest rest** — 10 minutes without a screen: water, a window, a walk. Then a warm-up.
- **Remove the distraction** — close the tab, put the phone away; the thought that distracted you goes to the Inbox.

> ⚠️ The first week is the observation week. Methods are not offered (except "Help anyway"): without it there is nothing to compare with later.

---

## 🔍 Review and experiments

### Week tiles

- **First pomodoro** — how late you are to the first session window; without a schedule, the time of the first pomodoro. Less is better.
- **Idle** — the average time between pomodoros. Less is better.
- **🐸 first** — on how many days the frog was the first pomodoro.
- **Postponed** — how many times you put off tasks that were already due.
- **Distractions** — the share of pomodoro time in flagged windows. Windows only.

The arrow compares with last week, "base" with the observation week. "—" means "not enough data", not zero.

### Experiment of the week

One hypothesis a week, for example "If the 🐸 has a first step, I start earlier". The metric is counted for you. At the end of the week comes a verdict: 15% better — "works", 15% worse — "worse", otherwise "no difference". Fewer than three days of data — "not enough data".

A method that works moves to the top of the episode sheet by itself.

> 💡 A week is short. "No difference" is a reason to repeat the experiment for another week, not to drop it.

### Well-being and work

The link of sleep and energy to idle time and the 🐸 appears once both the good and the bad days have at least three days. It is an observation, not proof.

### Procrastination scale

9 questions once a month. The metrics show behavior, the scale shows how you feel about it yourself. A lower score means less procrastination.

---

## 🪟 Windows and distractions

> Windows only. The tracker records the active window every 5 seconds. The data stays on this computer only: it goes neither to sync nor to the AI; windows during pomodoros are kept for 60 days, those outside pomodoros for 14.

### Where to look

- **Review → Windows** — the whole day: apps, tabs, share of distractions.
- **Task → ⋮ → "Task windows"** — what was open during all pomodoros of this task.
- **Done → ⋮ → "What was open"** — one pomodoro.
- **Review → Episodes → "What was instead"** — what you were busy with during the idle time before the start.

### Flag distractions

A flag next to YouTube, social networks, messengers — right in the window list. The distraction signal, the "Distractions" tile and the red rows depend on the flags.

> 💡 Do not flag your work browser as a whole: flag individual tabs by title.

---

## ✨ AI hints

> The AI (DeepSeek V4.1 Flash) does not chat with you. It fills in three places: first steps for a task, a hint for a thought and the weekly review. Without a key everything runs on rules.

### Connect

1. **platform.deepseek.com** — create an API key and top up the balance. A weekly review costs about a tenth of a cent.
2. **Settings → AI** — turn it on, paste the key, press "Check".

### What is sent to DeepSeek

- **Sent:** the task text, its category and direction, the thought from the episode sheet, weekly numbers.
- **Not sent:** windows, "where did you stop" notes, keys and tokens.

The DeepSeek server is in China. The key is stored on this device only; on the phone it is entered separately.

> ⚠️ The AI is not a psychologist and does not diagnose. If the text shows that the trouble is not about the task, the app offers to talk to someone close or a professional instead of giving a hint.

---

## ✍️ How to word things

### A milestone — checked with yes / no

- ✗ Work on the bot ⇒ ✓ The bot answers 3 commands in prod
- ✗ Sort out payments ⇒ ✓ The first payment from a real user went through
- ✗ Improve my English ⇒ ✓ Passed an interview in English

### A task — can be started in 5 minutes

- ✗ Build payments ⇒ ✓ Connect the Stripe webhook
- ✗ Write an article ⇒ ✓ Sketch a 5-point outline of the article

### A first step — a physical action

- ✗ Figure out the API ⇒ ✓ Open the API docs → Auth section
- ✗ Start the report ⇒ ✓ Create the file and write the title

### "If — then" — a concrete situation

- ✗ I'll do it in the morning ⇒ ✓ When I sit down after breakfast, I'll open api.dart
- ✗ When I have time ⇒ ✓ At 14:00 after lunch — the first step of the 🐸

On the left are pastimes, they never end. On the right are actions and results, they get closed.

---

## ⚠️ Common mistakes

- **Five active directions.** It does not work. Two or three, the rest on pause.
- **A milestone for a quarter.** Too big — you cannot see movement. A step is 1–3 weeks.
- **The ladder as a to-do list.** A step is an outcome. Chores live in tasks with ⭐.
- **Eight tasks a day.** That is a wish list, not a plan. The 🐸 and two more.
- **A direction without categories.** Attention to it is not counted.
- **Skipping the observation week.** Then there is nothing to compare with.
- **Three experiments at once.** It is unclear what worked. One a week.
- **Scolding yourself for an empty day.** There are no streaks here on purpose: yesterday is data, not a verdict.

---

## ⌨️ Keys and input

1. **Space** — start / pause.
2. **Esc Esc** — stop (second press within 1.5 s).
3. **Ctrl+N** — add a task from anywhere.
4. **+ / −** — pomodoros of the first task, with Shift — by 4.
5. **F1** — this help.

### Smart input

`#category Description ~3` — category, description and 3 pomodoros. `Enter` — to the Inbox, `Ctrl+Enter` — to "Today". Click the pomodoro count: +1, with Alt — −1, with Shift — ×4.

---

## 📚 Why it works

> The methods come from approaches that were tested in studies. They are self-observation tools, not treatment.

- **CBT** reduces procrastination more than other approaches (a meta-analysis of 24 studies). In an internet program the effect was there even without a specialist.
- **"If — then" plans** help more the more concrete the situation is and the more often you repeat the plan (642 tests).
- **ACT** — do not wait for the unpleasant feeling to go away, act for what matters (53 studies of online programs).
- **Behavioral activation** — action before motivation.
- **Self-forgiveness** after procrastinating reduces procrastination the next time.
- **The "observation → cause → method → reflection" loop** inside a planner was tested with the chatbot Moa.

- [van Eerde & Klingsieck, 2018 — meta-analysis of procrastination interventions](https://ris.uni-paderborn.de/record/29118)
- [Rozental et al., 2015 — internet-based CBT, RCT](https://pubmed.ncbi.nlm.nih.gov/25939016/)
- [Sheeran, Listrom, Gollwitzer, 2024 — "if — then" plans, 642 tests](https://kops.uni-konstanz.de/handle/123456789/69905)
- [Klimczak et al., 2023 — online ACT, 53 RCTs](https://informahealthcare.com/doi/full/10.1080/16506073.2023.2178498)
- [Furukawa et al., 2025 — RESiLIENT, CBT skills in an app](https://www.kyoto-u.ac.jp/en/research-news/2025-04-25)
- [Wohl, Pychyl, Bennett, 2010 — self-forgiveness and procrastination](https://doi.org/10.1016/j.paid.2010.01.029)
- [Lee et al., 2025 — Moa, a chatbot inside a planner](https://mhealth.jmir.org/2025/1/e53133)

> ⚠️ If low mood, anxiety or insomnia last for weeks, that is a reason to talk to a specialist, not to reconfigure the app.
