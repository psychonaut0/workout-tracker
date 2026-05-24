# workout-tracker

Personal gym-logging app. Track exercises and the **top working-set weight** per exercise over time (progressive overload is the whole point — see the recomp notes below). Private, data stays on my own infrastructure. **Not** a portfolio project.

> Status: **idea / not started.** This README is a capture of the intent + the decisions made so far + the reference data the app needs. Build later.

## What it needs to do

- Log a session: per exercise, the working sets (weight × reps), and flag/track the **top set** (heaviest for the day) and PRs.
- Show progression over time per exercise (the top-weight trend is the key view).
- Optional: reps/RIR notes, bodyweight log (ties into the cut/recomp tracking).

## Decisions so far

- **Usage**: phone at the gym + desktop for review → **phone + desktop, synced.**
- **Storage**: "save locally" = my own stuff, not a third-party cloud. Leaning **self-host on the homelab** (one small web app + DB, reached from phone over Tailscale / existing reverse proxy) so sync is trivial (single source of truth). Offline-first PWA + sync is the fallback if gym connectivity is flaky.
- **Not decided yet**: exact sync model (homelab-hosted vs offline-first+sync), stack, whether to model the split structure below or keep exercises free-form.

## Open questions for the build session

- Homelab-hosted single DB vs offline-first PWA with sync? (gym phone connectivity is the deciding factor)
- Stack (the homelab + `infra` context suggests Go backend + small web frontend, but a single-file PWA could be enough).
- Pre-seed the exercise list from my current split (below), or keep it free-form and let it grow?

## Reference: current training split

Source of truth lives in the knowledge vault: `personal/knowledge/wiki/projects/fitness-recomp.md` (and its source export). Copied here so the app's seed data / data model is at hand.

**4-day Upper/Lower/Push/Pull**, each muscle ~2×/week, 12–16 sets/muscle/week.
Mon Upper A (push) · Tue Lower A (quad) · Wed off · Thu Upper B (pull) · Fri Lower B (posterior chain) · weekend off / walks.

Loading scheme:
- Compounds: 6–8 reps @ 1–0 RIR (neural-dominant, Type-II-leaning lifter — strongest here).
- Isolation: 10–15 reps @ 1–2 RIR, pump sets to failure.
- **Progressive overload (log it):** compounds +1.25–2.5 kg at top of rep range; isolation +1 rep per 1–2 sessions, then add weight.
- Rest: heavy compounds 2.5–3 min · accessory 90s–2min · isolation 60–90s.

### Upper A — push
| Exercise | Sets × Reps | RIR |
|---|---|---|
| Incline bench press (Panatta) | 2 warm + 4×6–8 | 1–0 |
| Chest press (horizontal) | 3×8–10 | 1 |
| Seated DB shoulder press | 3×8–10 | 1 |
| DB lateral raise | 3×10–12 | 1 |
| Reverse pec deck / face pull | 3×12–15 | 1 |
| Rope triceps pushdown | 3×10–12 | 1 |
| Overhead rope extension | 3×10–12 | 1 |

### Lower A — quad + calf
| Exercise | Sets × Reps | RIR |
|---|---|---|
| Hack squat | 2 warm + 4×6–8 | 1–0 |
| Leg press (feet high/wide) | 3×10–12 | 1 |
| Leg extension | 3×10–12 | 1 |
| Seated leg curl | 3×8–10 | 1 |
| Standing calf raise (weighted) | 4×10–12 | 0–1 |

### Upper B — pull
| Exercise | Sets × Reps | RIR |
|---|---|---|
| Lat pulldown (wide pronated) | 2 warm + 4×6–8 | 1–0 |
| Row (Panatta, wide) | 4×8–10 | 1 |
| Iliac pulldown (close neutral) | 3×10–12 | 1 |
| Cable row (close neutral) | 3×10–12 | 1 |
| Preacher curl (barbell) | 3×8–10 | 1 |
| Cable hammer curl | 3×10–12 | 1 |
| Cable curl | 3×12–15 | 0–1 |

### Lower B — posterior chain
| Exercise | Sets × Reps | RIR |
|---|---|---|
| Romanian deadlift (cornerstone) | 2 warm + 4×6–8 | 1 |
| Hack squat (depth focus, moderate) | 3×10–12 | 1 |
| Lying leg curl | 4×8–10 | 1 |
| Unilateral leg extension | 3×12–15 | 0–1 |
| Seated calf raise | 4×12–15 | 0–1 |

Back-grip rotation: the four back movements alternate weekly between wide-pronated and close-neutral grips for varied stimulus.

### Weekly volume status (for reference)
chest 10 · back 14 · front-delt 6 · lat-delt 6 (low) · rear-delt 3 (low) · biceps 9 · triceps 6 (borderline) · quads 16 · hams 11 · glutes 7 (borderline) · calves 8. Planned bump after 4–6 wk if recovery holds: +1 lateral raise (Upper A & B), +1 face pull (Upper B), +1 rope ext (Upper A).

## Related
- Knowledge vault: `personal/knowledge/wiki/projects/fitness-recomp.md` — full recomp plan, nutrition, supplements, tracking protocol.
- The export also ships a self-contained React/Recharts weight-chart component — reusable for the bodyweight-trend view.
