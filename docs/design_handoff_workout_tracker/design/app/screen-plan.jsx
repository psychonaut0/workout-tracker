// screen-plan.jsx — Plan & Settings: manage the split template (days +
// per-day exercises) and the exercise library (create / edit exercises).
const { useState: useStatePlan } = React;

const DOW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// ── shared form controls ──────────────────────────────────────────────────
function Field({ label, children, hint }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--faint)', marginBottom: 8 }}>{label}</div>
      {children}
      {hint && <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 6 }}>{hint}</div>}
    </div>
  );
}

function TextInput({ value, onChange, placeholder }) {
  return (
    <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} style={{
      width: '100%', height: 46, padding: '0 14px', boxSizing: 'border-box',
      background: 'var(--surface-3)', border: '1px solid var(--line)', borderRadius: 'calc(var(--radius) * 0.6)',
      color: 'var(--text)', fontSize: 15, fontFamily: 'inherit', outline: 'none',
    }} />
  );
}

function ChipSelect({ value, options, onChange }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
      {options.map((o) => {
        const val = Array.isArray(o) ? o[0] : o;
        const lbl = Array.isArray(o) ? o[1] : o;
        const on = val === value;
        return (
          <button key={val} onClick={() => onChange(val)} style={{
            padding: '8px 13px', borderRadius: 99, cursor: 'pointer', fontSize: 13, fontWeight: 600,
            border: `1px solid ${on ? 'transparent' : 'var(--line-strong)'}`,
            background: on ? 'var(--accent)' : 'var(--surface)', color: on ? 'var(--accent-ink)' : 'var(--dim)',
          }}>{lbl}</button>
        );
      })}
    </div>
  );
}

function Toggle({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} style={{
      width: 50, height: 30, borderRadius: 99, border: 'none', cursor: 'pointer', position: 'relative',
      background: on ? 'var(--accent)' : 'var(--surface-3)', transition: 'background .15s', flexShrink: 0,
    }}>
      <span style={{ position: 'absolute', top: 3, left: on ? 23 : 3, width: 24, height: 24, borderRadius: 99, background: on ? 'var(--accent-ink)' : 'var(--dim)', transition: 'left .15s' }} />
    </button>
  );
}

function NumField({ value, onChange, step = 1, suffix, weight = false }) {
  return <window.Stepper value={value} onChange={onChange} step={step} suffix={suffix} weight={weight} width={132} />;
}

function PrimaryBtn({ children, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled} style={{
      width: '100%', height: 52, border: 'none', borderRadius: 'var(--radius)', cursor: disabled ? 'default' : 'pointer',
      background: disabled ? 'var(--surface-3)' : 'var(--accent)', color: disabled ? 'var(--faint)' : 'var(--accent-ink)',
      fontFamily: 'var(--display)', fontSize: 16, fontWeight: 700,
    }}>{children}</button>
  );
}

// ── section label inside editors ─────────────────────────────────────────
function PlanSection({ children, hint }) {
  return (
    <div style={{ margin: '20px 2px 11px' }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--faint)' }}>{children}</div>
      {hint && <div style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--faint)', marginTop: 5, textTransform: 'none', letterSpacing: 0, opacity: 0.85 }}>{hint}</div>}
    </div>
  );
}

// ── a single exercise slot within a training day (the prescription) ───────
function SlotRow({ slot, index, total, expanded, onToggle, onChange, onMove, onRemove }) {
  const ex = window.EX[slot.ex];
  if (!ex) return null;
  const upd = (patch) => onChange({ ...slot, ...patch });
  const reBtn = (dir, dis) => (
    <button onClick={(e) => { e.stopPropagation(); onMove(dir); }} disabled={dis} style={{
      width: 28, height: 30, border: 'none', background: 'var(--surface-3)', color: dis ? 'var(--faint)' : 'var(--dim)',
      borderRadius: dir < 0 ? 'calc(var(--radius) * 0.4) 0 0 calc(var(--radius) * 0.4)' : '0 calc(var(--radius) * 0.4) calc(var(--radius) * 0.4) 0',
      cursor: dis ? 'default' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: dis ? 0.4 : 1,
    }}><span style={{ width: 13, display: 'inline-flex', transform: dir < 0 ? 'none' : 'rotate(180deg)' }}>{Icons.arrowUp}</span></button>
  );
  return (
    <div style={{ background: 'var(--surface)', border: `1px solid ${expanded ? 'var(--line-strong)' : 'var(--line)'}`, borderRadius: 'calc(var(--radius) * 0.6)', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px' }}>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700, color: 'var(--faint)', width: 16, flexShrink: 0 }}>{index + 1}</span>
        <div onClick={onToggle} style={{ flex: 1, minWidth: 0, cursor: 'pointer' }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--faint)', marginTop: 1 }}>{slot.work}×{slot.repLow}–{slot.repHigh} · RIR {slot.rir}{ex.warm ? ` · ${slot.warm}wu` : ''}</div>
        </div>
        <div style={{ display: 'flex', gap: 2, flexShrink: 0 }}>
          {reBtn(-1, index === 0)}
          {reBtn(1, index === total - 1)}
          <button onClick={(e) => { e.stopPropagation(); onRemove(); }} style={{ width: 30, height: 30, marginLeft: 5, border: 'none', background: 'var(--surface-3)', color: 'var(--faint)', borderRadius: 'calc(var(--radius) * 0.4)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ width: 15, display: 'inline-flex' }}>{Icons.trash}</span></button>
        </div>
        <span onClick={onToggle} style={{ width: 16, display: 'inline-flex', color: 'var(--faint)', cursor: 'pointer', flexShrink: 0, transform: expanded ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>{Icons.chevron}</span>
      </div>
      {expanded && (
        <div style={{ padding: '2px 12px 13px' }}>
          <div style={{ display: 'flex', gap: 10 }}>
            <div style={{ flex: 1 }}><Field label="Working sets"><NumField value={slot.work} onChange={(v) => upd({ work: Math.max(1, v) })} /></Field></div>
            <div style={{ flex: 1 }}><Field label="Warmups"><NumField value={slot.warm} onChange={(v) => upd({ warm: Math.max(0, v) })} /></Field></div>
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <div style={{ flex: 1 }}><Field label="Rep low"><NumField value={slot.repLow} onChange={(v) => upd({ repLow: Math.max(1, v), repHigh: Math.max(slot.repHigh, v) })} /></Field></div>
            <div style={{ flex: 1 }}><Field label="Rep high"><NumField value={slot.repHigh} onChange={(v) => upd({ repHigh: Math.max(slot.repLow, v) })} /></Field></div>
          </div>
          <Field label="RIR target"><TextInput value={String(slot.rir)} onChange={(v) => upd({ rir: v })} placeholder="1" /></Field>
        </div>
      )}
    </div>
  );
}

// ── day (split template) editor ───────────────────────────────────────────
function DayEditor({ slug, onBack, onChange }) {
  const existing = slug ? window.DAY[slug] : null;
  const toSlot = (item) => { const r = window.resolveSlot(item); return { ex: r.exId, work: r.work, repLow: r.repLow, repHigh: r.repHigh, rir: r.rir, warm: r.warm }; };
  const [draft, setDraft] = useStatePlan(() => existing
    ? { name: existing.name, focus: existing.focus, day: existing.day, items: existing.items.map(toSlot) }
    : { name: '', focus: '', day: 'Mon', items: [] });
  const [sheet, setSheet] = useStatePlan(false);
  const [openSlot, setOpenSlot] = useStatePlan(-1);
  const set = (patch) => setDraft((d) => ({ ...d, ...patch }));

  const move = (i, dir) => {
    const items = [...draft.items];
    const j = i + dir;
    if (j < 0 || j >= items.length) return;
    [items[i], items[j]] = [items[j], items[i]];
    set({ items });
  };
  const remove = (i) => { set({ items: draft.items.filter((_, k) => k !== i) }); setOpenSlot(-1); };
  const changeSlot = (i, ns) => set({ items: draft.items.map((s, k) => (k === i ? ns : s)) });
  const add = (exId) => {
    if (!draft.items.some((s) => s.ex === exId)) set({ items: [...draft.items, toSlot(exId)] });
    setSheet(false);
  };

  const save = () => {
    if (!draft.name.trim()) return;
    if (existing) window.updateDay(slug, draft);
    else window.addDay(draft);
    onChange();
    onBack();
  };
  const del = () => { window.deleteDay(slug); onChange(); onBack(); };

  return (
    <div className="app-scroll" style={{ flex: 1, overflowY: 'auto', padding: '8px 16px 104px' }}>
      <Field label="Day name"><TextInput value={draft.name} onChange={(v) => set({ name: v })} placeholder="e.g. Upper A" /></Field>
      <Field label="Focus"><TextInput value={draft.focus} onChange={(v) => set({ focus: v })} placeholder="e.g. Push" /></Field>
      <Field label="Scheduled day"><ChipSelect value={draft.day} options={DOW} onChange={(v) => set({ day: v })} /></Field>

      <PlanSection hint="Sets, reps & RIR are set per day — tap a row to tune this day's prescription.">Exercises · {draft.items.length}</PlanSection>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 7, marginBottom: 10 }}>
        {draft.items.map((slot, i) => (
          <SlotRow key={slot.ex} slot={slot} index={i} total={draft.items.length}
            expanded={openSlot === i} onToggle={() => setOpenSlot(openSlot === i ? -1 : i)}
            onChange={(ns) => changeSlot(i, ns)} onMove={(dir) => move(i, dir)} onRemove={() => remove(i)} />
        ))}
      </div>
      <button onClick={() => setSheet(true)} style={{
        width: '100%', height: 44, marginBottom: 22, border: '1px dashed var(--line-strong)', background: 'transparent',
        color: 'var(--dim)', borderRadius: 'calc(var(--radius) * 0.6)', cursor: 'pointer',
        fontFamily: 'var(--mono)', fontSize: 12.5, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, whiteSpace: 'nowrap',
      }}>
        <span style={{ width: 15, display: 'inline-flex' }}>{Icons.plus}</span>Add exercise
      </button>

      <PrimaryBtn onClick={save} disabled={!draft.name.trim()}>{existing ? 'Save changes' : 'Create training day'}</PrimaryBtn>
      {existing && (
        <button onClick={del} style={{ width: '100%', height: 46, marginTop: 10, border: 'none', background: 'transparent', color: 'var(--faint)', cursor: 'pointer', fontFamily: 'var(--mono)', fontSize: 12.5, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <span style={{ width: 15, display: 'inline-flex' }}>{Icons.trash}</span>Delete day
        </button>
      )}

      <window.ExerciseSheet open={sheet} selected={null} onSelect={add} onClose={() => setSheet(false)} />
    </div>
  );
}

// ── exercise editor (identity + stats + default prescription) ─────────────
function ExerciseEditor({ id, onBack, onChange }) {
  const existing = id ? window.EX[id] : null;
  const [d, setD] = useStatePlan(() => existing
    ? { name: existing.name, muscle: existing.muscle, equip: existing.equip, compound: existing.compound, repLow: existing.repLow, repHigh: existing.repHigh, work: existing.work, warm: existing.warm, rir: existing.rir, base: existing.base, step: existing.step }
    : { name: '', muscle: 'chest', equip: '', compound: false, repLow: 8, repHigh: 12, work: 3, warm: 0, rir: '1', base: 40, step: 2.5 });
  const set = (patch) => setD((x) => ({ ...x, ...patch }));
  const pr = existing ? window.prFor(id) : 0;

  const save = () => {
    if (!d.name.trim()) return;
    if (existing) window.updateExercise(id, d);
    else window.addExercise(d);
    onChange();
    onBack();
  };

  return (
    <div className="app-scroll" style={{ flex: 1, overflowY: 'auto', padding: '8px 16px 104px' }}>
      {/* identity */}
      <Field label="Exercise name"><TextInput value={d.name} onChange={(v) => set({ name: v })} placeholder="e.g. Incline Bench Press" /></Field>
      <Field label="Muscle group"><ChipSelect value={d.muscle} options={Object.entries(window.MUSCLES)} onChange={(v) => set({ muscle: v })} /></Field>
      <Field label="Equipment / machine"><TextInput value={d.equip} onChange={(v) => set({ equip: v })} placeholder="e.g. Panatta, Hammer Strength…" /></Field>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 2px' }}>
        <div>
          <div style={{ fontSize: 14.5, fontWeight: 600, color: 'var(--text)' }}>Compound lift</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 2 }}>Movement trait · drives rest & warmups</div>
        </div>
        <Toggle on={d.compound} onChange={(v) => set({ compound: v, warm: v && d.warm === 0 ? 2 : d.warm })} />
      </div>

      {/* stats */}
      <PlanSection hint="Tracked per exercise across every split.">Stats</PlanSection>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'calc(var(--radius) * 0.6)', marginBottom: 10 }}>
        <div style={{ width: 34, height: 34, borderRadius: 'calc(var(--radius) * 0.5)', background: 'var(--surface-3)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <span style={{ width: 18, display: 'inline-flex' }}>{Icons.bolt}</span>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)' }}>Personal record</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 1 }}>Best logged top set</div>
        </div>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 15, fontWeight: 700, color: pr ? 'var(--text)' : 'var(--faint)' }}>{pr ? `${window.fmtWt(pr)}${window.uLabel()}` : '—'}</div>
      </div>
      <Field label="Start weight" hint="Top-set seed for the first session — history drives suggestions after that.">
        <NumField value={d.base} step={d.step} weight onChange={(v) => set({ base: Math.max(0, v) })} />
      </Field>

      {/* default prescription (seeds new template slots) */}
      <PlanSection hint="Pre-fills a day's slot when you add this exercise. Tune the real sets/reps per day in the Split.">Default prescription</PlanSection>
      <div style={{ display: 'flex', gap: 10 }}>
        <div style={{ flex: 1 }}><Field label="Rep low"><NumField value={d.repLow} onChange={(v) => set({ repLow: Math.max(1, v), repHigh: Math.max(d.repHigh, v) })} /></Field></div>
        <div style={{ flex: 1 }}><Field label="Rep high"><NumField value={d.repHigh} onChange={(v) => set({ repHigh: Math.max(d.repLow, v) })} /></Field></div>
      </div>
      <div style={{ display: 'flex', gap: 10 }}>
        <div style={{ flex: 1 }}><Field label="Working sets"><NumField value={d.work} onChange={(v) => set({ work: Math.max(1, v) })} /></Field></div>
        <div style={{ flex: 1 }}><Field label="Warmups"><NumField value={d.warm} onChange={(v) => set({ warm: Math.max(0, v) })} /></Field></div>
      </div>
      <Field label="RIR target"><TextInput value={String(d.rir)} onChange={(v) => set({ rir: v })} placeholder="1" /></Field>

      <PrimaryBtn onClick={save} disabled={!d.name.trim()}>{existing ? 'Save exercise' : 'Create exercise'}</PrimaryBtn>
    </div>
  );
}

// ── split list (tab) ──────────────────────────────────────────────────────
function SplitTab({ onEdit, onNew }) {
  return (
    <div className="app-scroll" style={{ flex: 1, overflowY: 'auto', padding: '8px 16px 104px' }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)', marginBottom: 14 }}>{window.DAYS.length} training days in rotation</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9, marginBottom: 14 }}>
        {window.DAYS.map((day) => (
          <button key={day.slug} onClick={() => onEdit(day.slug)} style={{
            display: 'flex', alignItems: 'center', gap: 13, textAlign: 'left', cursor: 'pointer',
            padding: '14px 14px', background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'var(--radius)',
          }}>
            <div style={{ width: 42, textAlign: 'center', flexShrink: 0 }}>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 10, color: 'var(--faint)', textTransform: 'uppercase' }}>{day.day}</div>
              <div style={{ fontFamily: 'var(--display)', fontSize: 15, fontWeight: 700, color: 'var(--accent)', marginTop: 2 }}>{day.items.length}</div>
            </div>
            <div style={{ width: 1, alignSelf: 'stretch', background: 'var(--line)' }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 15.5, fontWeight: 600, color: 'var(--text)' }}>{day.name}</div>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{day.focus}</div>
            </div>
            <span style={{ width: 16, display: 'inline-flex', color: 'var(--faint)', flexShrink: 0 }}>{Icons.chevron}</span>
          </button>
        ))}
      </div>
      <button onClick={onNew} style={{
        width: '100%', height: 50, border: '1px dashed var(--line-strong)', background: 'transparent',
        color: 'var(--dim)', borderRadius: 'var(--radius)', cursor: 'pointer',
        fontFamily: 'var(--mono)', fontSize: 13, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, whiteSpace: 'nowrap',
      }}>
        <span style={{ width: 16, display: 'inline-flex' }}>{Icons.plus}</span>New training day
      </button>
    </div>
  );
}

// ── exercise library (tab) ────────────────────────────────────────────────
function LibraryTab({ onEdit, onNew }) {
  const groups = {};
  window.EXERCISES.forEach((ex) => { (groups[ex.muscle] = groups[ex.muscle] || []).push(ex); });
  const order = Object.keys(window.MUSCLES).filter((m) => groups[m]);
  return (
    <div className="app-scroll" style={{ flex: 1, overflowY: 'auto', padding: '8px 16px 104px' }}>
      <button onClick={onNew} style={{
        width: '100%', height: 48, marginBottom: 18, border: 'none', background: 'var(--accent)',
        color: 'var(--accent-ink)', borderRadius: 'var(--radius)', cursor: 'pointer',
        fontFamily: 'var(--display)', fontSize: 15, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, whiteSpace: 'nowrap',
      }}>
        <span style={{ width: 17, display: 'inline-flex' }}>{Icons.plus}</span>New exercise
      </button>
      {order.map((m) => (
        <div key={m} style={{ marginBottom: 16 }}>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--faint)', margin: '2px 2px 8px' }}>{window.MUSCLES[m]}</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {groups[m].map((ex) => {
              const pr = window.prFor(ex.id);
              return (
                <button key={ex.id} onClick={() => onEdit(ex.id)} style={{
                  display: 'flex', alignItems: 'center', gap: 11, textAlign: 'left', cursor: 'pointer',
                  padding: '11px 13px', background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'calc(var(--radius) * 0.65)',
                }}>
                  <span style={{ width: 6, height: 6, borderRadius: 99, background: ex.compound ? 'var(--accent)' : 'var(--line-strong)', flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14.5, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
                    <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.equip || window.MUSCLES[ex.muscle]}{ex.compound ? ' · compound' : ''}</div>
                  </div>
                  {pr > 0 && <span style={{ fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700, color: 'var(--dim)', flexShrink: 0 }}>{window.fmtWt(pr)}<span style={{ fontSize: 9, color: 'var(--faint)' }}>{window.uLabel()}</span></span>}
                  <span style={{ width: 15, display: 'inline-flex', color: 'var(--faint)', flexShrink: 0 }}>{Icons.edit}</span>
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

// ── overlay shell ─────────────────────────────────────────────────────────
function SettingsOverlay({ onClose, onChange }) {
  const [tab, setTab] = useStatePlan('split');
  const [editor, setEditor] = useStatePlan(null); // {kind:'day'|'exercise', id?}

  const title = editor
    ? (editor.kind === 'day' ? (editor.id ? 'Edit training day' : 'New training day') : (editor.id ? 'Edit exercise' : 'New exercise'))
    : 'Plan & Settings';

  return (
    <div style={{ flex: 1, minHeight: 0, background: 'var(--bg)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 56, flexShrink: 0, background: 'var(--bg)', borderBottom: '1px solid var(--line)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '4px 16px 12px' }}>
          {editor ? (
            <button onClick={() => setEditor(null)} style={{ width: 36, height: 36, borderRadius: 99, border: '1px solid var(--line)', background: 'var(--surface)', color: 'var(--dim)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <span style={{ width: 18, display: 'inline-flex', transform: 'rotate(180deg)' }}>{Icons.chevron}</span>
            </button>
          ) : (
            <div style={{ width: 36, height: 36, borderRadius: 'calc(var(--radius) * 0.55)', background: 'var(--surface-3)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <span style={{ width: 20, display: 'inline-flex' }}>{Icons.plan}</span>
            </div>
          )}
          <div style={{ flex: 1, fontFamily: 'var(--display)', fontSize: 19, fontWeight: 700, color: 'var(--text)' }}>{title}</div>
        </div>
        {!editor && (
          <div style={{ display: 'flex', gap: 6, padding: '0 16px 12px' }}>
            {[['split', 'Split'], ['exercises', 'Exercises']].map(([id, lbl]) => {
              const on = tab === id;
              return (
                <button key={id} onClick={() => setTab(id)} style={{
                  flex: 1, height: 36, borderRadius: 'calc(var(--radius) * 0.6)', cursor: 'pointer',
                  border: `1px solid ${on ? 'transparent' : 'var(--line)'}`,
                  background: on ? 'var(--surface-3)' : 'transparent', color: on ? 'var(--text)' : 'var(--faint)',
                  fontFamily: 'var(--mono)', fontSize: 12.5, fontWeight: 700,
                  boxShadow: on ? 'inset 0 0 0 1px var(--line-strong)' : 'none',
                }}>{lbl}</button>
              );
            })}
          </div>
        )}
      </div>

      {!editor && tab === 'split' && <SplitTab onEdit={(slug) => setEditor({ kind: 'day', id: slug })} onNew={() => setEditor({ kind: 'day' })} />}
      {!editor && tab === 'exercises' && <LibraryTab onEdit={(id) => setEditor({ kind: 'exercise', id })} onNew={() => setEditor({ kind: 'exercise' })} />}
      {editor && editor.kind === 'day' && <DayEditor slug={editor.id} onBack={() => setEditor(null)} onChange={onChange} />}
      {editor && editor.kind === 'exercise' && <ExerciseEditor id={editor.id} onBack={() => setEditor(null)} onChange={onChange} />}
    </div>
  );
}

Object.assign(window, { SettingsOverlay, Field, TextInput, ChipSelect, Toggle, PrimaryBtn });
