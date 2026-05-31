// screen-progress.jsx — per-exercise progression, switchable across metrics.
const { useState: useStateP } = React;

const SearchGlyph = (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round">
    <circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" />
  </svg>
);

// tappable selector that opens the exercise sheet
function ExerciseSelector({ ex, onOpen }) {
  return (
    <button onClick={onOpen} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left',
      padding: '12px 13px', background: 'var(--surface)', border: '1px solid var(--line)',
      borderRadius: 'var(--radius)', cursor: 'pointer', marginBottom: 16,
    }}>
      <div style={{ width: 38, height: 38, borderRadius: 'calc(var(--radius) * 0.5)', background: 'var(--surface-3)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <span style={{ width: 20, display: 'inline-flex' }}>{Icons.dumbbell}</span>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 2 }}>{window.MUSCLES[ex.muscle]} · {ex.equip}</div>
      </div>
      <span style={{ fontFamily: 'var(--mono)', fontSize: 10, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'var(--dim)', display: 'flex', alignItems: 'center', gap: 5 }}>
        Change<span style={{ width: 15, display: 'inline-flex', color: 'var(--faint)' }}>{Icons.chevron}</span>
      </span>
    </button>
  );
}

// searchable, muscle-grouped bottom sheet
function ExerciseSheet({ open, selected, onSelect, onClose, showBodyweight }) {
  const [q, setQ] = useStateP('');
  React.useEffect(() => { if (open) setQ(''); }, [open]);
  if (!open) return null;
  const ql = q.trim().toLowerCase();
  const bwMatch = showBodyweight && ('bodyweight'.includes(ql) || 'weight'.includes(ql) || ql === '');

  const groups = {};
  window.EXERCISES.forEach((ex) => {
    if (ql && !ex.name.toLowerCase().includes(ql) && !window.MUSCLES[ex.muscle].toLowerCase().includes(ql)) return;
    (groups[ex.muscle] = groups[ex.muscle] || []).push(ex);
  });
  const muscleOrder = Object.keys(window.MUSCLES).filter((m) => groups[m]);
  const count = muscleOrder.reduce((a, m) => a + groups[m].length, 0);

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 50, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.55)' }} />
      <div style={{
        position: 'relative', background: 'var(--surface-2)', borderTop: '1px solid var(--line-strong)',
        borderTopLeftRadius: 'calc(var(--radius) * 1.5)', borderTopRightRadius: 'calc(var(--radius) * 1.5)',
        maxHeight: '84%', display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        {/* grabber + title */}
        <div style={{ padding: '10px 16px 4px', flexShrink: 0 }}>
          <div style={{ width: 38, height: 4, borderRadius: 99, background: 'var(--line-strong)', margin: '0 auto 14px' }} />
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
            <span style={{ fontFamily: 'var(--display)', fontSize: 19, fontWeight: 700, color: 'var(--text)' }}>Choose exercise</span>
            <button onClick={onClose} style={{ fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 600, color: 'var(--dim)', background: 'none', border: 'none', cursor: 'pointer' }}>Done</button>
          </div>
          {/* search */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '0 12px', height: 42, background: 'var(--surface-3)', borderRadius: 'calc(var(--radius) * 0.7)', marginBottom: 6 }}>
            <span style={{ color: 'var(--faint)', display: 'inline-flex' }}>{SearchGlyph}</span>
            <input value={q} onChange={(e) => setQ(e.target.value)} autoFocus placeholder="Search exercises or muscle…"
              style={{ flex: 1, background: 'none', border: 'none', outline: 'none', color: 'var(--text)', fontFamily: 'var(--sans, inherit)', fontSize: 15 }} />
            {q && <button onClick={() => setQ('')} style={{ background: 'none', border: 'none', color: 'var(--faint)', cursor: 'pointer', fontFamily: 'var(--mono)', fontSize: 16, lineHeight: 1, padding: 0 }}>×</button>}
          </div>
        </div>

        {/* list */}
        <div className="app-scroll" style={{ overflowY: 'auto', padding: '6px 16px 30px' }}>
          {count === 0 && !bwMatch && (
            <div style={{ textAlign: 'center', padding: '40px 0', fontFamily: 'var(--mono)', fontSize: 13, color: 'var(--faint)' }}>No exercises match “{q}”.</div>
          )}
          {bwMatch && (
            <div style={{ marginBottom: 14 }}>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--faint)', margin: '2px 2px 8px' }}>Tracking</div>
              <button onClick={() => { onSelect(window.BW_ID); onClose(); }} style={{
                width: '100%', display: 'flex', alignItems: 'center', gap: 11, textAlign: 'left', cursor: 'pointer',
                padding: '11px 13px', borderRadius: 'calc(var(--radius) * 0.65)',
                background: selected === window.BW_ID ? 'var(--accent)' : 'var(--surface)',
                border: `1px solid ${selected === window.BW_ID ? 'transparent' : 'var(--line)'}`,
              }}>
                <span style={{ width: 20, display: 'inline-flex', color: selected === window.BW_ID ? 'var(--accent-ink)' : 'var(--accent)', flexShrink: 0 }}>{Icons.scale}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14.5, fontWeight: 600, color: selected === window.BW_ID ? 'var(--accent-ink)' : 'var(--text)' }}>Bodyweight</div>
                  <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: selected === window.BW_ID ? 'var(--accent-ink)' : 'var(--faint)', opacity: selected === window.BW_ID ? 0.7 : 1, marginTop: 1 }}>Daily log</div>
                </div>
                {selected === window.BW_ID && <span style={{ width: 16, display: 'inline-flex', color: 'var(--accent-ink)' }}>{Icons.check}</span>}
              </button>
            </div>
          )}
          {muscleOrder.map((m) => (
            <div key={m} style={{ marginBottom: 14 }}>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--faint)', margin: '2px 2px 8px' }}>{window.MUSCLES[m]}</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {groups[m].map((ex) => {
                  const on = ex.id === selected;
                  return (
                    <button key={ex.id} onClick={() => { onSelect(ex.id); onClose(); }} style={{
                      display: 'flex', alignItems: 'center', gap: 11, textAlign: 'left', cursor: 'pointer',
                      padding: '11px 13px', borderRadius: 'calc(var(--radius) * 0.65)',
                      background: on ? 'var(--accent)' : 'var(--surface)',
                      border: `1px solid ${on ? 'transparent' : 'var(--line)'}`,
                    }}>
                      {ex.compound
                        ? <span style={{ width: 6, height: 6, borderRadius: 99, background: on ? 'var(--accent-ink)' : 'var(--accent)', flexShrink: 0 }} />
                        : <span style={{ width: 6, height: 6, borderRadius: 99, background: on ? 'rgba(0,0,0,0.3)' : 'var(--line-strong)', flexShrink: 0 }} />}
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 14.5, fontWeight: 600, color: on ? 'var(--accent-ink)' : 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
                        <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: on ? 'var(--accent-ink)' : 'var(--faint)', opacity: on ? 0.7 : 1, marginTop: 1 }}>{ex.equip}{ex.compound ? ' · compound' : ''}</div>
                      </div>
                      {on && <span style={{ width: 16, display: 'inline-flex', color: 'var(--accent-ink)' }}>{Icons.check}</span>}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// metric definitions — each derives a value from a per-session block
const METRICS = [
  { id: 'top',    label: 'Top set',  short: 'Top set',  wt: true,  reps: true,  pr: true,
    val: (d) => d.weight },
  { id: 'e1rm',   label: 'Est. 1RM', short: 'Est. 1RM', wt: true,  reps: false, pr: false,
    val: (d) => d.e1rm },
  { id: 'volume', label: 'Volume',   short: 'Volume',   wt: true,  reps: false, pr: false,
    val: (d) => d.volume },
  { id: 'reps',   label: 'Top reps', short: 'Reps',     wt: false, reps: false, pr: false,
    val: (d) => d.reps },
];

// build a full per-session series for an exercise (all metrics available)
function fullSeriesFor(exId) {
  return window.SESSIONS
    .filter((s) => s.exercises.some((e) => e.exerciseId === exId))
    .map((s) => {
      const blk = s.exercises.find((e) => e.exerciseId === exId);
      const work = blk.sets.filter((st) => !st.isWarmup);
      const volume = work.reduce((a, st) => a + st.weightKg * st.reps, 0);
      return {
        date: s.date, dateObj: s.dateObj, weight: blk.topWeight, reps: blk.topReps,
        isPr: blk.isPr, e1rm: window.est1rm(blk.topWeight, blk.topReps), volume: Math.round(volume),
      };
    })
    .sort((a, b) => a.dateObj - b.dateObj);
}

const fmtVal = (v, m) => (m.id === 'volume' ? Math.round(v).toLocaleString('en-US') : window.fmtKg(v));
const metricUnit = (m) => (m.wt ? window.uLabel() : '');

function MetricTabs({ value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 6, padding: '0 16px', marginBottom: 16 }}>
      {METRICS.map((m) => {
        const on = m.id === value;
        return (
          <button key={m.id} onClick={() => onChange(m.id)} style={{
            flex: 1, height: 34, borderRadius: 'calc(var(--radius) * 0.6)', cursor: 'pointer',
            border: `1px solid ${on ? 'transparent' : 'var(--line)'}`,
            background: on ? 'var(--surface-3)' : 'transparent',
            color: on ? 'var(--text)' : 'var(--faint)',
            fontFamily: 'var(--mono)', fontSize: 11.5, fontWeight: 700, letterSpacing: '0.02em',
            display: 'flex', alignItems: 'center', justifyContent: 'center', whiteSpace: 'nowrap',
            boxShadow: on ? 'inset 0 0 0 1px var(--line-strong)' : 'none',
          }}>{m.short}</button>
        );
      })}
    </div>
  );
}

function BigStat({ label, value, unit, accent }) {
  return (
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--faint)', marginBottom: 6 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 2 }}>
        <span style={{ fontFamily: 'var(--display)', fontSize: 22, fontWeight: 700, letterSpacing: '-0.02em', color: accent ? 'var(--accent)' : 'var(--text)', lineHeight: 1 }}>{value}</span>
        {unit && <span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--dim)' }}>{unit}</span>}
      </div>
    </div>
  );
}

function ProgressScreen({ selected, onSelect, onOpenPicker, onChange }) {
  if (selected === window.BW_ID) {
    return <window.BodyweightProgress onOpenPicker={onOpenPicker} onChange={onChange} />;
  }
  const exId = selected || 'incline-bench';
  const [metricId, setMetricId] = useStateP('top');
  const metric = METRICS.find((m) => m.id === metricId);
  const ex = window.EX[exId];

  const full = fullSeriesFor(exId);
  const unit = metricUnit(metric);
  // chart series remaps the active metric onto `weight` (what LineChart reads), converting to display unit
  const series = full.map((d) => ({ ...d, weight: metric.wt ? window.fromKg(metric.val(d)) : metric.val(d), reps: d.reps, isPr: metric.pr && d.isPr }));

  const latest = series[series.length - 1];
  const first = series[0];
  const best = Math.max(...series.map((s) => s.weight));
  const delta = latest.weight - first.weight;

  return (
    <div>
      <div style={{ padding: '0 16px', marginBottom: 16 }}>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 5 }}>Progression</div>
        <div style={{ fontFamily: 'var(--display)', fontSize: 28, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', whiteSpace: 'nowrap' }}>{metric.label} trend</div>
      </div>

      <div style={{ padding: '0 16px', marginBottom: 14 }}>
        <ExerciseSelector ex={ex} onOpen={onOpenPicker} />
      </div>

      {/* metric switcher */}
      <MetricTabs value={metricId} onChange={setMetricId} />

      <div style={{ padding: '0 16px' }}>
        {/* chart */}
        <Card style={{ padding: '16px 8px 10px', marginBottom: 14 }}>
          <LineChart key={metricId + unit} series={series} height={210} unit={unit} showReps={metric.reps} />
        </Card>

        {/* stat row */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 22 }}>
          <Card style={{ padding: '13px 14px' }}><BigStat label="Current" value={fmtVal(latest.weight, metric)} unit={unit + (metric.reps ? ` ×${latest.reps}` : '')} /></Card>
          <Card style={{ padding: '13px 14px' }}><BigStat label="Best" value={fmtVal(best, metric)} unit={unit} accent /></Card>
          <Card style={{ padding: '13px 14px' }}><BigStat label="12wk Δ" value={`${delta >= 0 ? '+' : ''}${fmtVal(delta, metric)}`} unit={unit} /></Card>
        </div>

        {/* session log */}
        <window.SectionLabel action={<span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--dim)' }}>{series.length} sessions</span>}>{metric.label} by session</window.SectionLabel>
        <Card pad={false} style={{ overflow: 'hidden' }}>
          {[...series].reverse().map((s, i, arr) => {
            const prev = arr[i + 1];
            const diff = prev ? s.weight - prev.weight : 0;
            return (
              <div key={s.date} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderBottom: i < arr.length - 1 ? '1px solid var(--line)' : 'none' }}>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 12, color: 'var(--dim)', width: 58, flexShrink: 0 }}>{window.fmtDate(s.date)}</span>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 14, fontWeight: 700, color: 'var(--text)', whiteSpace: 'nowrap' }}>{fmtVal(s.weight, metric)}{unit && <span style={{ fontSize: 10, color: 'var(--faint)' }}>{unit}</span>}{metric.reps && <span style={{ color: 'var(--faint)', fontWeight: 400 }}> × {s.reps}</span>}</span>
                <div style={{ flex: 1 }} />
                {s.isPr && <PRBadge small />}
                {!s.isPr && diff !== 0 && (
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 11.5, fontWeight: 600, color: diff > 0 ? 'var(--accent)' : 'var(--faint)' }}>{diff > 0 ? '+' : ''}{fmtVal(diff, metric)}</span>
                )}
                {!s.isPr && diff === 0 && <span style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)' }}>=</span>}
              </div>
            );
          })}
        </Card>
      </div>
    </div>
  );
}

Object.assign(window, { ProgressScreen, ExerciseSheet });
