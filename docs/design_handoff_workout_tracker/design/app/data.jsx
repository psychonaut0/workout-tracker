// data.jsx — seed data + generated history for the workout tracker.
// Modeled on the real repo: exercises (muscle_group), day_templates
// (4-day Upper/Lower/Push/Pull split), sessions, sets (weight_kg, reps,
// rir, is_warmup, is_top_set, is_pr). Units: kg. All deterministic.

// ── deterministic PRNG so the demo data is stable across reloads ──────────
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(20260530);
const jitter = (n) => (rnd() - 0.5) * n;
const roundTo = (v, step) => Math.round(v / step) * step;

// ── muscle groups ────────────────────────────────────────────────────────
const MUSCLES = {
  chest: 'Chest', back: 'Back', shoulders: 'Shoulders', quads: 'Quads',
  hams: 'Hamstrings', glutes: 'Glutes', calves: 'Calves',
  biceps: 'Biceps', triceps: 'Triceps',
};

// ── exercise catalogue (base = ~12 weeks ago top-set kg) ──────────────────
// rate = kg gained per week (compounds climb faster), step = plate increment.
const EXERCISES = [
  // Upper A — push
  { id: 'incline-bench', name: 'Incline Bench Press', equip: 'Panatta', muscle: 'chest', compound: true, base: 72.5, rate: 1.0, step: 2.5, repLow: 6, repHigh: 8, rir: '1–0', warm: 2, work: 4 },
  { id: 'chest-press',   name: 'Chest Press',         equip: 'Horizontal', muscle: 'chest', compound: false, base: 64, rate: 0.7, step: 2.0, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 3 },
  { id: 'db-shoulder-press', name: 'Seated DB Shoulder Press', equip: 'Dumbbell', muscle: 'shoulders', compound: false, base: 24, rate: 0.35, step: 2.0, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 3 },
  { id: 'lateral-raise', name: 'DB Lateral Raise',    equip: 'Dumbbell', muscle: 'shoulders', compound: false, base: 11, rate: 0.18, step: 1.0, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'reverse-pec',   name: 'Reverse Pec Deck',    equip: 'Machine', muscle: 'shoulders', compound: false, base: 40, rate: 0.4, step: 2.5, repLow: 12, repHigh: 15, rir: '1', warm: 0, work: 3 },
  { id: 'tri-pushdown',  name: 'Rope Triceps Pushdown', equip: 'Cable', muscle: 'triceps', compound: false, base: 32, rate: 0.4, step: 2.5, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'oh-tri-ext',    name: 'Overhead Rope Extension', equip: 'Cable', muscle: 'triceps', compound: false, base: 27, rate: 0.35, step: 2.5, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  // Lower A — quad
  { id: 'hack-squat',    name: 'Hack Squat',          equip: 'Machine', muscle: 'quads', compound: true, base: 120, rate: 2.2, step: 5.0, repLow: 6, repHigh: 8, rir: '1–0', warm: 2, work: 4 },
  { id: 'leg-press',     name: 'Leg Press',           equip: 'Feet high/wide', muscle: 'quads', compound: false, base: 200, rate: 2.5, step: 5.0, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'leg-ext',       name: 'Leg Extension',       equip: 'Machine', muscle: 'quads', compound: false, base: 60, rate: 0.8, step: 5.0, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'seated-curl',   name: 'Seated Leg Curl',     equip: 'Machine', muscle: 'hams', compound: false, base: 55, rate: 0.7, step: 5.0, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 3 },
  { id: 'standing-calf', name: 'Standing Calf Raise', equip: 'Weighted', muscle: 'calves', compound: false, base: 90, rate: 1.0, step: 5.0, repLow: 10, repHigh: 12, rir: '0–1', warm: 0, work: 4 },
  // Upper B — pull
  { id: 'lat-pulldown',  name: 'Lat Pulldown',        equip: 'Wide pronated', muscle: 'back', compound: true, base: 75, rate: 1.1, step: 2.5, repLow: 6, repHigh: 8, rir: '1–0', warm: 2, work: 4 },
  { id: 'panatta-row',   name: 'Row',                 equip: 'Panatta, wide', muscle: 'back', compound: false, base: 80, rate: 1.0, step: 5.0, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 4 },
  { id: 'iliac-pulldown',name: 'Iliac Pulldown',      equip: 'Close neutral', muscle: 'back', compound: false, base: 60, rate: 0.7, step: 2.5, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'cable-row',     name: 'Cable Row',           equip: 'Close neutral', muscle: 'back', compound: false, base: 65, rate: 0.7, step: 2.5, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'preacher-curl', name: 'Preacher Curl',       equip: 'Barbell', muscle: 'biceps', compound: false, base: 32, rate: 0.35, step: 2.5, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 3 },
  { id: 'hammer-curl',   name: 'Cable Hammer Curl',   equip: 'Cable', muscle: 'biceps', compound: false, base: 27, rate: 0.3, step: 2.5, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'cable-curl',    name: 'Cable Curl',          equip: 'Cable', muscle: 'biceps', compound: false, base: 22, rate: 0.25, step: 2.5, repLow: 12, repHigh: 15, rir: '0–1', warm: 0, work: 3 },
  // Lower B — posterior chain
  { id: 'rdl',           name: 'Romanian Deadlift',   equip: 'Barbell', muscle: 'hams', compound: true, base: 100, rate: 1.6, step: 2.5, repLow: 6, repHigh: 8, rir: '1', warm: 2, work: 4 },
  { id: 'hack-depth',    name: 'Hack Squat',          equip: 'Depth focus', muscle: 'quads', compound: false, base: 90, rate: 1.4, step: 5.0, repLow: 10, repHigh: 12, rir: '1', warm: 0, work: 3 },
  { id: 'lying-curl',    name: 'Lying Leg Curl',      equip: 'Machine', muscle: 'hams', compound: false, base: 50, rate: 0.6, step: 5.0, repLow: 8, repHigh: 10, rir: '1', warm: 0, work: 4 },
  { id: 'uni-leg-ext',   name: 'Unilateral Leg Extension', equip: 'Machine', muscle: 'quads', compound: false, base: 30, rate: 0.4, step: 2.5, repLow: 12, repHigh: 15, rir: '0–1', warm: 0, work: 3 },
  { id: 'seated-calf',   name: 'Seated Calf Raise',   equip: 'Machine', muscle: 'calves', compound: false, base: 45, rate: 0.6, step: 5.0, repLow: 12, repHigh: 15, rir: '0–1', warm: 0, work: 4 },
];
const EX = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));

// ── day templates (the 4-day split) ──────────────────────────────────────
const DAYS = [
  { slug: 'upper-a', name: 'Upper A', focus: 'Push', day: 'Mon',
    items: ['incline-bench', 'chest-press', 'db-shoulder-press', 'lateral-raise', 'reverse-pec', 'tri-pushdown', 'oh-tri-ext'] },
  { slug: 'lower-a', name: 'Lower A', focus: 'Quad + Calf', day: 'Tue',
    items: ['hack-squat', 'leg-press', 'leg-ext', 'seated-curl', 'standing-calf'] },
  { slug: 'upper-b', name: 'Upper B', focus: 'Pull', day: 'Thu',
    items: ['lat-pulldown', 'panatta-row', 'iliac-pulldown', 'cable-row', 'preacher-curl', 'hammer-curl', 'cable-curl'] },
  { slug: 'lower-b', name: 'Lower B', focus: 'Posterior Chain', day: 'Fri',
    items: ['rdl', 'hack-depth', 'lying-curl', 'uni-leg-ext', 'seated-calf'] },
];
const DAY = Object.fromEntries(DAYS.map((d) => [d.slug, d]));

// ── date helpers ──────────────────────────────────────────────────────────
const TODAY = new Date(2026, 4, 30); // Sat May 30 2026
function addDays(base, n) { const d = new Date(base); d.setDate(d.getDate() + n); return d; }
function iso(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
const NEWEST_MONDAY = new Date(2026, 4, 25); // Mon May 25 2026
const WEEKS = 12;
const dayOffset = { 'upper-a': 0, 'lower-a': 1, 'upper-b': 3, 'lower-b': 4 };

// progression curve: gentle S — newbie-ish gains then steady, tiny plateaus
function levelAt(ex, w) {
  const t = w / (WEEKS - 1);                 // 0..1
  const eased = t + 0.12 * Math.sin(t * Math.PI); // slight early bow
  let lvl = ex.base + ex.rate * eased * (WEEKS - 1);
  // a mild deload dip mid-cycle on compounds
  if (ex.compound && w === 6) lvl -= ex.step;
  return lvl;
}

// build set list for one exercise in one session
function buildSets(ex, w, sessionId, prevBest) {
  const target = roundTo(levelAt(ex, w) + jitter(ex.step * 0.4), ex.step);
  const sets = [];
  let n = 1;
  for (let i = 0; i < ex.warm; i++) {
    sets.push({
      id: `${sessionId}:${ex.id}:w${i}`, exerciseId: ex.id, setNumber: n++,
      weightKg: roundTo(target * (0.5 + i * 0.18), ex.step), reps: 8 - i * 2,
      rir: 4, isWarmup: true, isTopSet: false, isPr: false,
    });
  }
  // working sets: build to the top set (heaviest, last-but-strongest)
  const topReps = ex.repLow + Math.round((ex.repHigh - ex.repLow) * (0.4 + jitter(0.3)));
  for (let i = 0; i < ex.work; i++) {
    const isTop = i === ex.work - 1;
    const wkWeight = isTop ? target : roundTo(target - ex.step * (ex.work - 1 - i) * 0.5, ex.step);
    const reps = isTop ? Math.max(ex.repLow, topReps) : ex.repHigh - i;
    sets.push({
      id: `${sessionId}:${ex.id}:${i}`, exerciseId: ex.id, setNumber: n++,
      weightKg: wkWeight, reps, rir: i === ex.work - 1 ? 0 : 1,
      isWarmup: false, isTopSet: isTop, isPr: false,
    });
  }
  const topSet = sets.find((s) => s.isTopSet);
  const isPr = topSet.weightKg > prevBest;
  topSet.isPr = isPr;
  return { sets, topWeight: topSet.weightKg, topReps: topSet.reps, isPr };
}

// ── generate sessions across the cycle ────────────────────────────────────
const SESSIONS = [];
const bestSoFar = {}; // exId -> best top weight
for (let w = 0; w < WEEKS; w++) {
  const monday = addDays(NEWEST_MONDAY, -(WEEKS - 1 - w) * 7);
  DAYS.forEach((tmpl) => {
    const date = addDays(monday, dayOffset[tmpl.slug]);
    if (date > TODAY) return;
    const sessionId = `s-${iso(date)}-${tmpl.slug}`;
    const exBlocks = [];
    let prCount = 0;
    tmpl.items.forEach((exId) => {
      const ex = EX[exId];
      const prev = bestSoFar[exId] ?? 0;
      const built = buildSets(ex, w, sessionId, prev);
      if (built.isPr) { bestSoFar[exId] = built.topWeight; prCount++; }
      exBlocks.push({ exerciseId: exId, ...built });
    });
    // duration ~ items * 9min + noise
    const dur = Math.round(tmpl.items.length * 9 + 18 + jitter(14));
    SESSIONS.push({
      id: sessionId, date: iso(date), dateObj: date,
      daySlug: tmpl.slug, splitLabel: `${tmpl.name} — ${tmpl.focus}`,
      week: w, exercises: exBlocks, prCount, durationMin: dur,
    });
  });
}
SESSIONS.sort((a, b) => b.dateObj - a.dateObj); // newest first

// per-exercise top-set time series (for the progression chart)
function seriesFor(exId) {
  return SESSIONS
    .filter((s) => s.exercises.some((e) => e.exerciseId === exId))
    .map((s) => {
      const blk = s.exercises.find((e) => e.exerciseId === exId);
      return { date: s.date, dateObj: s.dateObj, weight: blk.topWeight, reps: blk.topReps, isPr: blk.isPr };
    })
    .sort((a, b) => a.dateObj - b.dateObj);
}

// estimated 1RM (Epley) from a top set
function est1rm(weight, reps) { return Math.round(weight * (1 + reps / 30)); }

// previous session's block for an exercise (for "last time" reference)
function lastTimeFor(exId, beforeDate) {
  const past = SESSIONS.filter((s) => s.date < beforeDate && s.exercises.some((e) => e.exerciseId === exId))
    .sort((a, b) => b.dateObj - a.dateObj);
  if (!past.length) return null;
  const s = past[0];
  return { date: s.date, block: s.exercises.find((e) => e.exerciseId === exId) };
}

// ── bodyweight log (recomp: slow downward drift) ──────────────────────────
const BODYWEIGHT = [];
for (let i = WEEKS * 7; i >= 0; i -= 2) {
  const d = addDays(TODAY, -i);
  const t = 1 - i / (WEEKS * 7);
  const wt = roundTo(84.5 - 4.2 * t + jitter(0.5), 0.1);
  BODYWEIGHT.push({ date: iso(d), weight: wt });
}

// ── weekly volume (sets per muscle this week) from README reference ───────
const WEEKLY_VOLUME = [
  { muscle: 'Quads', sets: 16, target: 16 }, { muscle: 'Back', sets: 14, target: 14 },
  { muscle: 'Hamstrings', sets: 11, target: 12 }, { muscle: 'Chest', sets: 10, target: 12 },
  { muscle: 'Biceps', sets: 9, target: 10 }, { muscle: 'Calves', sets: 8, target: 9 },
  { muscle: 'Glutes', sets: 7, target: 9 }, { muscle: 'Front Delt', sets: 6, target: 6 },
  { muscle: 'Lat Delt', sets: 6, target: 9 }, { muscle: 'Triceps', sets: 6, target: 9 },
  { muscle: 'Rear Delt', sets: 3, target: 6 },
];

// "today's" planned session — next in rotation (Upper A — Push)
const TODAY_PLAN = DAY['upper-a'];

// recent PRs across all exercises (last 3 weeks)
const RECENT_PRS = SESSIONS
  .filter((s) => s.prCount > 0)
  .flatMap((s) => s.exercises.filter((e) => e.isPr).map((e) => ({
    date: s.date, exId: e.exerciseId, weight: e.topWeight, reps: e.topReps,
  })))
  .slice(0, 6);

// ── mutation helpers (create/edit split days + exercises) ─────────────────
function slugify(name) {
  const base = (name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'item';
  let s = base, i = 2;
  while (EX[s] || DAY[s]) { s = `${base}-${i++}`; }
  return s;
}
function addExercise(def) {
  const id = slugify(def.name);
  const ex = {
    id, name: def.name, equip: def.equip || '', muscle: def.muscle || 'chest',
    compound: !!def.compound, base: def.base || 20, rate: def.compound ? 1.0 : 0.4,
    step: def.step || 2.5, repLow: def.repLow || 8, repHigh: def.repHigh || 12,
    rir: def.rir || '1', warm: def.warm != null ? def.warm : (def.compound ? 2 : 0),
    work: def.work || 3, custom: true,
  };
  EXERCISES.push(ex); EX[id] = ex; return ex;
}
function updateExercise(id, patch) { if (EX[id]) Object.assign(EX[id], patch); return EX[id]; }
function addDay(def) {
  const slug = slugify(def.name);
  const d = { slug, name: def.name, focus: def.focus || '', day: def.day || 'Mon', items: def.items || [], custom: true };
  DAYS.push(d); DAY[slug] = d; return d;
}
function updateDay(slug, patch) { if (DAY[slug]) Object.assign(DAY[slug], patch); return DAY[slug]; }
function deleteDay(slug) {
  const i = DAYS.findIndex((d) => d.slug === slug);
  if (i >= 0) DAYS.splice(i, 1);
  delete DAY[slug];
}
// log (or replace) a bodyweight entry; weight stored in kg, list kept ascending
function logBodyweight(kg, dateIso) {
  const date = dateIso || iso(TODAY);
  const existing = BODYWEIGHT.find((b) => b.date === date);
  if (existing) existing.weight = roundTo(kg, 0.1);
  else BODYWEIGHT.push({ date, weight: roundTo(kg, 0.1) });
  BODYWEIGHT.sort((a, b) => (a.date < b.date ? -1 : 1));
  return BODYWEIGHT;
}
// normalize a template item (string id OR slot object {ex, work, ...}) into a
// full prescription, falling back to the exercise's default values.
function resolveSlot(item) {
  const exId = typeof item === 'string' ? item : (item && item.ex);
  const ex = EX[exId] || {};
  const o = (typeof item === 'string' || !item) ? {} : item;
  const pick = (k, d) => (o[k] != null ? o[k] : (ex[k] != null ? ex[k] : d));
  return {
    exId,
    work: pick('work', 3),
    repLow: pick('repLow', 8),
    repHigh: pick('repHigh', 12),
    rir: pick('rir', '1'),
    warm: pick('warm', 0),
  };
}
// best recorded top-set (kg) for an exercise, derived from logged history
function prFor(exId) {
  const tops = SESSIONS.filter((s) => s.exercises.some((e) => e.exerciseId === exId))
    .map((s) => s.exercises.find((e) => e.exerciseId === exId).topWeight);
  return tops.length ? Math.max(...tops) : 0;
}

Object.assign(window, {
  MUSCLES, EXERCISES, EX, DAYS, DAY, SESSIONS, BODYWEIGHT, WEEKLY_VOLUME,
  TODAY, TODAY_PLAN, RECENT_PRS, iso, addDays,
  seriesFor, est1rm, lastTimeFor, roundTo,
  slugify, addExercise, updateExercise, addDay, updateDay, deleteDay, logBodyweight,
  resolveSlot, prFor,
});
