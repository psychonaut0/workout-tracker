// screen-log.jsx — the active gym workflow: live set logging, steppers,
// RIR, "last time" reference, auto top-set + PR detection, rest timer.
const { useState: useStateL, useEffect: useEffectL, useRef: useRefL } = React;

// ── small interactive controls ────────────────────────────────────────────
function Stepper({ value, onChange, step = 2.5, suffix, width = 96, weight = false }) {
  const btn = (dir) => (
    <button onClick={(e) => { e.stopPropagation(); onChange(Math.max(0, +(value + dir * step).toFixed(2))); }}
      style={{
        width: 25, height: 34, border: 'none', background: 'var(--surface-3)', color: 'var(--text)',
        borderRadius: 'calc(var(--radius) * 0.4)', cursor: 'pointer', flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
      <span style={{ width: 13, display: 'inline-flex' }}>{dir < 0 ? Icons.minus : Icons.plus}</span>
    </button>
  );
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4, width }}>
      {btn(-1)}
      <div style={{ flex: 1, minWidth: 0, textAlign: 'center', display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 2 }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 15, fontWeight: 700, color: 'var(--text)' }}>{weight ? window.fmtWt(value) : window.fmtKg(value)}</span>
        {(weight || suffix) && <span style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--faint)' }}>{weight ? window.uLabel() : suffix}</span>}
      </div>
      {btn(1)}
    </div>
  );
}

function RirPicker({ value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 3 }}>
      {[0, 1, 2, 3].map((r) => (
        <button key={r} onClick={(e) => { e.stopPropagation(); onChange(r); }} style={{
          width: 17, height: 30, border: 'none', cursor: 'pointer', flexShrink: 0,
          borderRadius: 'calc(var(--radius) * 0.35)',
          background: value === r ? 'var(--accent)' : 'var(--surface-3)',
          color: value === r ? 'var(--accent-ink)' : 'var(--dim)',
          fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700,
        }}>{r}</button>
      ))}
    </div>
  );
}

// ── rest timer (sticky) ───────────────────────────────────────────────────
function RestTimer({ total, onDone, onSkip }) {
  const [left, setLeft] = useStateL(total);
  useEffectL(() => {
    if (left <= 0) { onDone(); return; }
    const t = setTimeout(() => setLeft((l) => l - 1), 1000);
    return () => clearTimeout(t);
  }, [left]);
  const mm = Math.floor(left / 60), ss = left % 60;
  const pct = 1 - left / total;
  const R = 16, C = 2 * Math.PI * R;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 13, padding: '11px 14px',
      background: 'var(--surface-2)', border: '1px solid var(--line-strong)',
      borderRadius: 'var(--radius)', boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
    }}>
      <div style={{ position: 'relative', width: 40, height: 40, flexShrink: 0 }}>
        <svg width="40" height="40" style={{ transform: 'rotate(-90deg)' }}>
          <circle cx="20" cy="20" r={R} fill="none" stroke="var(--surface-3)" strokeWidth="3" />
          <circle cx="20" cy="20" r={R} fill="none" stroke="var(--accent)" strokeWidth="3"
                  strokeDasharray={C} strokeDashoffset={C * (1 - pct)} strokeLinecap="round" />
        </svg>
        <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent)', width: 16, margin: 'auto' }}>{Icons.timer}</span>
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--faint)' }}>Rest</div>
        <div style={{ fontFamily: 'var(--display)', fontSize: 22, fontWeight: 700, color: 'var(--text)', lineHeight: 1 }}>{mm}:{String(ss).padStart(2, '0')}</div>
      </div>
      <button onClick={() => setLeft((l) => l + 30)} style={{ height: 34, padding: '0 12px', border: '1px solid var(--line-strong)', background: 'transparent', color: 'var(--dim)', borderRadius: 'calc(var(--radius) * 0.5)', fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>+30s</button>
      <button onClick={onSkip} style={{ height: 34, padding: '0 14px', border: 'none', background: 'var(--accent)', color: 'var(--accent-ink)', borderRadius: 'calc(var(--radius) * 0.5)', fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>Skip</button>
    </div>
  );
}

// ── build the editable session from the plan ──────────────────────────────
function buildBlock(item) {
  const slot = window.resolveSlot(item);
  const exId = slot.exId;
  const ex = window.EX[exId];
  const lt = window.lastTimeFor(exId, '2026-05-30');
  const lastTop = lt ? lt.block.topWeight : ex.base;
  const suggested = window.roundTo(lastTop + (ex.compound ? ex.step : 0), ex.step);
  const sets = [];
  for (let i = 0; i < slot.warm; i++) {
    sets.push({ id: `${exId}-w${i}`, weight: window.roundTo(suggested * (0.5 + i * 0.18), ex.step), reps: 8 - i * 2, rir: 4, isWarmup: true, done: false });
  }
  for (let i = 0; i < slot.work; i++) {
    sets.push({ id: `${exId}-${i}`, weight: suggested, reps: slot.repLow, rir: 1, isWarmup: false, done: false });
  }
  return { exId, slot, sets, lastTime: lt };
}
function buildSessionState(plan) {
  return (plan.items || []).map((item) => buildBlock(item));
}

function SetRow({ set, ex, onChange, onToggle, isTop, isPr }) {
  const done = set.done;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 6, padding: '7px 3px 7px 0',
      opacity: set.isWarmup && !done ? 0.7 : 1,
    }}>
      <div style={{ width: 26, flexShrink: 0, textAlign: 'center' }}>
        {set.isWarmup
          ? <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)' }}>W</span>
          : <span style={{ fontFamily: 'var(--mono)', fontSize: 13, fontWeight: 700, color: done ? 'var(--accent)' : 'var(--dim)' }}>{set.workIdx}</span>}
      </div>
      {done ? (
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 15, fontWeight: 700, color: 'var(--text)' }}>{window.fmtWt(set.weight)}<span style={{ fontSize: 11, color: 'var(--faint)' }}>{window.uLabel()}</span></span>
          <span style={{ color: 'var(--faint)', fontSize: 12 }}>×</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 15, fontWeight: 700, color: 'var(--text)' }}>{set.reps}</span>
          {!set.isWarmup && <span style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)' }}>RIR {set.rir}</span>}
          <div style={{ flex: 1 }} />
          {isPr && <PRBadge small />}
          {isTop && !isPr && <Tag tone="solid" style={{ fontSize: 9.5 }}>TOP</Tag>}
        </div>
      ) : (
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
          <Stepper value={set.weight} step={ex.step} width={100} weight onChange={(v) => onChange({ ...set, weight: v })} />
          <Stepper value={set.reps} step={1} onChange={(v) => onChange({ ...set, reps: v })} width={76} />
          {!set.isWarmup
            ? <RirPicker value={set.rir} onChange={(v) => onChange({ ...set, rir: v })} />
            : <div style={{ width: 77 }} />}
        </div>
      )}
      <button onClick={() => onToggle(set)} style={{
        width: 32, height: 34, flexShrink: 0, borderRadius: 'calc(var(--radius) * 0.45)', cursor: 'pointer',
        border: done ? 'none' : '1.5px solid var(--line-strong)',
        background: done ? 'var(--accent)' : 'transparent',
        color: done ? 'var(--accent-ink)' : 'var(--faint)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <span style={{ width: 16, display: 'inline-flex' }}>{Icons.check}</span>
      </button>
    </div>
  );
}

function ExerciseBlock({ block, expanded, onExpand, onUpdate, onRemove, best }) {
  const ex = window.EX[block.exId];
  const slot = block.slot || window.resolveSlot(block.exId);
  const working = block.sets.filter((s) => !s.isWarmup);
  working.forEach((s, i) => { s.workIdx = i + 1; });
  const doneWork = working.filter((s) => s.done);
  const completedTop = doneWork.length ? Math.max(...doneWork.map((s) => s.weight)) : 0;
  const lt = block.lastTime;

  const setSet = (ns) => onUpdate(block.exId, block.sets.map((s) => (s.id === ns.id ? ns : s)));
  const toggleSet = (s) => {
    const wasDone = s.done;
    onUpdate(block.exId, block.sets.map((x) => (x.id === s.id ? { ...x, done: !x.done } : x)), !wasDone && !s.isWarmup ? ex : null);
  };
  const addSet = () => {
    const last = working[working.length - 1] || { weight: ex.base, reps: ex.repLow, rir: 1 };
    onUpdate(block.exId, [...block.sets, { id: `${ex.id}-x${block.sets.length}`, weight: last.weight, reps: last.reps, rir: 1, isWarmup: false, done: false }]);
  };

  const allDone = working.length > 0 && doneWork.length === working.length;
  return (
    <div style={{
      background: 'var(--surface)', border: `1px solid ${expanded ? 'var(--line-strong)' : 'var(--line)'}`,
      borderRadius: 'var(--radius)', overflow: 'hidden', marginBottom: 10,
    }}>
      {/* header */}
      <div onClick={onExpand} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', cursor: 'pointer' }}>
        <div style={{
          width: 36, height: 36, borderRadius: 'calc(var(--radius) * 0.5)', flexShrink: 0,
          background: allDone ? 'var(--accent)' : 'var(--surface-3)',
          color: allDone ? 'var(--accent-ink)' : 'var(--dim)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          {allDone ? <span style={{ width: 18, display: 'inline-flex' }}>{Icons.check}</span>
            : <span style={{ fontFamily: 'var(--mono)', fontSize: 13, fontWeight: 700 }}>{doneWork.length}/{working.length}</span>}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 2 }}>
            {window.MUSCLES[ex.muscle]} · {slot.work}×{slot.repLow}–{slot.repHigh} @ RIR {slot.rir}
          </div>
        </div>
        {completedTop > 0 && (
          <div style={{ textAlign: 'right', marginRight: 4 }}>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 14, fontWeight: 700, color: 'var(--text)' }}>{window.fmtWt(completedTop)}<span style={{ fontSize: 10, color: 'var(--faint)' }}>{window.uLabel()}</span></div>
            {completedTop > best && <div style={{ marginTop: 2 }}><PRBadge small /></div>}
          </div>
        )}
        <span style={{ width: 18, display: 'inline-flex', color: 'var(--faint)', transform: expanded ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>{Icons.chevron}</span>
      </div>

      {expanded && (
        <div style={{ padding: '0 14px 14px' }}>
          {/* last time reference */}
          {lt && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 10px', background: 'var(--surface-2)', borderRadius: 'calc(var(--radius) * 0.5)', marginBottom: 10 }}>
              <span style={{ width: 15, display: 'inline-flex', color: 'var(--faint)' }}>{Icons.history}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', textTransform: 'uppercase', letterSpacing: '0.06em' }}>Last · {window.daysAgo(lt.date)}</span>
              <div style={{ flex: 1 }} />
              <span style={{ fontFamily: 'var(--mono)', fontSize: 12.5, fontWeight: 700, color: 'var(--dim)', whiteSpace: 'nowrap' }}>{window.fmtWt(lt.block.topWeight)}{window.uLabel()} × {lt.block.topReps}</span>
            </div>
          )}
          {/* set rows */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 0 4px' }}>
            <span style={{ width: 26, flexShrink: 0, textAlign: 'center', fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--faint)' }}>SET</span>
            <span style={{ flex: 1, display: 'flex', justifyContent: 'space-between', fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--faint)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
              <span style={{ width: 100, textAlign: 'center' }}>Weight</span><span style={{ width: 76, textAlign: 'center' }}>Reps</span><span style={{ width: 77, textAlign: 'center' }}>RIR</span>
            </span>
            <span style={{ width: 32, flexShrink: 0 }} />
          </div>
          {block.sets.map((s) => (
            <SetRow key={s.id} set={s} ex={ex} isTop={!s.isWarmup && s.done && s.weight === completedTop}
                    isPr={!s.isWarmup && s.done && s.weight === completedTop && completedTop > best}
                    onChange={setSet} onToggle={toggleSet} />
          ))}
          <button onClick={addSet} style={{
            width: '100%', marginTop: 8, height: 38, border: '1px dashed var(--line-strong)', background: 'transparent',
            color: 'var(--dim)', borderRadius: 'calc(var(--radius) * 0.5)', cursor: 'pointer',
            fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, whiteSpace: 'nowrap',
          }}>
            <span style={{ width: 14, display: 'inline-flex' }}>{Icons.plus}</span>Add set
          </button>
          {onRemove && (
            <button onClick={onRemove} style={{
              width: '100%', marginTop: 8, height: 34, border: 'none', background: 'transparent',
              color: 'var(--faint)', borderRadius: 'calc(var(--radius) * 0.5)', cursor: 'pointer',
              fontFamily: 'var(--mono)', fontSize: 11.5, fontWeight: 600, letterSpacing: '0.04em',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            }}>
              <span style={{ width: 14, display: 'inline-flex' }}>{Icons.trash}</span>Remove exercise
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function ActiveSession({ plan, onClose, onFinish }) {
  const [blocks, setBlocks] = useStateL(() => buildSessionState(plan));
  const [expanded, setExpanded] = useStateL((plan.items || [])[0] || null);
  const [rest, setRest] = useStateL(null); // {total, key}
  const [elapsed, setElapsed] = useStateL(0);
  const [addOpen, setAddOpen] = useStateL(false);
  const scrollRef = useRefL(null);

  useEffectL(() => {
    const t = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const bestFor = (exId) => {
    const past = window.SESSIONS.filter((s) => s.exercises.some((e) => e.exerciseId === exId))
      .map((s) => s.exercises.find((e) => e.exerciseId === exId).topWeight);
    return past.length ? Math.max(...past) : 0;
  };

  const updateBlock = (exId, sets, restEx) => {
    setBlocks((bs) => bs.map((b) => (b.exId === exId ? { ...b, sets } : b)));
    if (restEx) setRest({ total: restEx.compound ? 180 : 90, key: Date.now() });
  };
  const addExerciseLive = (exId) => {
    setBlocks((bs) => (bs.some((b) => b.exId === exId) ? bs : [...bs, buildBlock(exId)]));
    setExpanded(exId);
    setAddOpen(false);
  };
  const removeBlock = (exId) => {
    setBlocks((bs) => bs.filter((b) => b.exId !== exId));
  };

  const totalWork = blocks.reduce((a, b) => a + b.sets.filter((s) => !s.isWarmup).length, 0);
  const doneWork = blocks.reduce((a, b) => a + b.sets.filter((s) => !s.isWarmup && s.done).length, 0);
  const mm = Math.floor(elapsed / 60), ss = elapsed % 60;
  const prCount = blocks.reduce((a, b) => {
    const ex = window.EX[b.exId];
    const done = b.sets.filter((s) => !s.isWarmup && s.done);
    if (!done.length) return a;
    const top = Math.max(...done.map((s) => s.weight));
    return a + (top > bestFor(b.exId) ? 1 : 0);
  }, 0);

  return (
    <div style={{ position: 'absolute', inset: 0, background: 'var(--bg)', zIndex: 40, display: 'flex', flexDirection: 'column' }}>
      {/* header */}
      <div style={{ paddingTop: 56, flexShrink: 0, background: 'var(--bg)', borderBottom: '1px solid var(--line)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '4px 16px 12px' }}>
          <button onClick={onClose} style={{ width: 36, height: 36, borderRadius: 99, border: '1px solid var(--line)', background: 'var(--surface)', color: 'var(--dim)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <span style={{ width: 18, display: 'inline-flex', transform: 'rotate(180deg)' }}>{Icons.chevron}</span>
          </button>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: 'var(--display)', fontSize: 18, fontWeight: 700, color: 'var(--text)', lineHeight: 1.1 }}>{plan.name} <span style={{ color: 'var(--faint)', fontWeight: 600 }}>· {plan.focus}</span></div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 2 }}>{doneWork}/{totalWork} sets{prCount > 0 ? ` · ${prCount} PR${prCount > 1 ? 's' : ''}` : ''}</div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 18, fontWeight: 700, color: 'var(--accent)', lineHeight: 1 }}>{mm}:{String(ss).padStart(2, '0')}</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--faint)', letterSpacing: '0.06em', marginTop: 2 }}>ELAPSED</div>
          </div>
        </div>
        <div style={{ height: 3, background: 'var(--surface-3)' }}>
          <div style={{ height: '100%', width: `${totalWork ? (doneWork / totalWork) * 100 : 0}%`, background: 'var(--accent)', transition: 'width .3s' }} />
        </div>
      </div>

      {/* exercise list */}
      <div ref={scrollRef} style={{ flex: 1, overflowY: 'auto', padding: '14px 16px 120px' }}>
        {blocks.length === 0 && (
          <div style={{ textAlign: 'center', padding: '40px 20px 30px' }}>
            <div style={{ width: 56, height: 56, borderRadius: 99, background: 'var(--surface)', border: '1px solid var(--line)', color: 'var(--faint)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 16px' }}>
              <span style={{ width: 26, display: 'inline-flex' }}>{Icons.dumbbell}</span>
            </div>
            <div style={{ fontFamily: 'var(--display)', fontSize: 18, fontWeight: 700, color: 'var(--text)' }}>Empty session</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 12, color: 'var(--faint)', marginTop: 6 }}>Add your first exercise to begin.</div>
          </div>
        )}
        {blocks.map((b) => (
          <ExerciseBlock key={b.exId} block={b} expanded={expanded === b.exId} best={bestFor(b.exId)}
            onExpand={() => setExpanded(expanded === b.exId ? null : b.exId)} onUpdate={updateBlock} onRemove={() => removeBlock(b.exId)} />
        ))}
        <button onClick={() => setAddOpen(true)} style={{
          width: '100%', height: 46, marginBottom: 10, border: '1px dashed var(--line-strong)', background: 'transparent',
          color: 'var(--dim)', borderRadius: 'var(--radius)', cursor: 'pointer',
          fontFamily: 'var(--mono)', fontSize: 13, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, whiteSpace: 'nowrap',
        }}>
          <span style={{ width: 16, display: 'inline-flex' }}>{Icons.plus}</span>Add exercise
        </button>
        <button onClick={() => onFinish({ plan, blocks, elapsed, prCount, doneWork })} disabled={doneWork === 0} style={{
          width: '100%', height: 52, border: 'none', borderRadius: 'var(--radius)',
          background: doneWork > 0 ? 'var(--accent)' : 'var(--surface-3)', color: doneWork > 0 ? 'var(--accent-ink)' : 'var(--faint)',
          cursor: doneWork > 0 ? 'pointer' : 'default', fontFamily: 'var(--display)', fontSize: 16, fontWeight: 700,
        }}>Finish workout</button>
      </div>

      {/* add-exercise picker */}
      <window.ExerciseSheet open={addOpen} selected={null} onSelect={addExerciseLive} onClose={() => setAddOpen(false)} />

      {/* rest timer (sticky) */}
      {rest && (
        <div style={{ position: 'absolute', left: 16, right: 16, bottom: 44, zIndex: 5 }}>
          <RestTimer key={rest.key} total={rest.total} onDone={() => setRest(null)} onSkip={() => setRest(null)} />
        </div>
      )}
    </div>
  );
}

Object.assign(window, { ActiveSession, Stepper, RirPicker, RestTimer });
