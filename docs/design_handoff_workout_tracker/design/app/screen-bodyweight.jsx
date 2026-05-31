// screen-bodyweight.jsx — bodyweight progress view + add-entry sheet.
const { useState: useStateBw, useEffect: useEffectBw } = React;

const BW_ID = '__bodyweight__';

// ── add / log entry bottom sheet (works in the active display unit) ───────
function AddWeightSheet({ open, onClose, onSave }) {
  const lastKg = window.BODYWEIGHT[window.BODYWEIGHT.length - 1].weight;
  const unit = window.uLabel();
  const stepU = unit === 'lb' ? 0.2 : 0.1;
  const [val, setVal] = useStateBw(() => Number(window.fromKg(lastKg).toFixed(1)));
  useEffectBw(() => { if (open) setVal(Number(window.fromKg(lastKg).toFixed(1))); }, [open]);
  if (!open) return null;

  const bump = (dir) => setVal((v) => Math.max(0, +(v + dir * stepU).toFixed(2)));
  const save = () => { window.logBodyweight(window.toKg(val), window.iso(window.TODAY)); onSave(); onClose(); };

  const Big = ({ dir }) => (
    <button onClick={() => bump(dir)} style={{
      width: 56, height: 56, borderRadius: 99, border: '1px solid var(--line-strong)', background: 'var(--surface-3)',
      color: 'var(--text)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    }}><span style={{ width: 22, display: 'inline-flex' }}>{dir < 0 ? Icons.minus : Icons.plus}</span></button>
  );

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 55, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.55)' }} />
      <div style={{
        position: 'relative', background: 'var(--surface-2)', borderTop: '1px solid var(--line-strong)',
        borderTopLeftRadius: 'calc(var(--radius) * 1.5)', borderTopRightRadius: 'calc(var(--radius) * 1.5)',
        padding: '10px 16px 34px',
      }}>
        <div style={{ width: 38, height: 4, borderRadius: 99, background: 'var(--line-strong)', margin: '0 auto 16px' }} />
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
          <span style={{ fontFamily: 'var(--display)', fontSize: 19, fontWeight: 700, color: 'var(--text)' }}>Log bodyweight</span>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)' }}>{window.fmtDate(window.iso(window.TODAY), { weekday: true })}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 22, padding: '26px 0 28px' }}>
          <Big dir={-1} />
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, minWidth: 150, justifyContent: 'center' }}>
            <span style={{ fontFamily: 'var(--display)', fontSize: 52, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.03em', lineHeight: 1 }}>{val.toFixed(1)}</span>
            <span style={{ fontFamily: 'var(--mono)', fontSize: 16, color: 'var(--dim)' }}>{unit}</span>
          </div>
          <Big dir={1} />
        </div>
        <button onClick={save} style={{
          width: '100%', height: 52, border: 'none', borderRadius: 'var(--radius)', background: 'var(--accent)',
          color: 'var(--accent-ink)', cursor: 'pointer', fontFamily: 'var(--display)', fontSize: 16, fontWeight: 700,
        }}>Save entry</button>
      </div>
    </div>
  );
}

function BwStat({ label, value, unit, accent }) {
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

// ── bodyweight progress (rendered inside the Progress tab) ────────────────
function BodyweightProgress({ onOpenPicker, onChange }) {
  const [addOpen, setAddOpen] = useStateBw(false);
  const bw = window.BODYWEIGHT;
  const unit = window.uLabel();
  const series = bw.map((b) => ({ date: b.date, dateObj: new Date(b.date + 'T00:00:00'), weight: window.fromKg(b.weight), reps: 0, isPr: false }));
  const latest = series[series.length - 1];
  const first = series[0];
  const lowest = Math.min(...series.map((s) => s.weight));
  const monthAgo = series.find((s) => (window.TODAY - s.dateObj) <= 30 * 86400000) || first;
  const delta30 = latest.weight - monthAgo.weight;
  const total = latest.weight - first.weight;

  return (
    <div>
      <div style={{ padding: '0 16px', marginBottom: 16 }}>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 5 }}>Progression</div>
        <div style={{ fontFamily: 'var(--display)', fontSize: 28, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', whiteSpace: 'nowrap' }}>Bodyweight trend</div>
      </div>

      {/* selector row (opens the picker to switch back to a lift) */}
      <div style={{ padding: '0 16px', marginBottom: 14 }}>
        <button onClick={onOpenPicker} style={{
          width: '100%', display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left',
          padding: '12px 13px', background: 'var(--surface)', border: '1px solid var(--line)',
          borderRadius: 'var(--radius)', cursor: 'pointer',
        }}>
          <div style={{ width: 38, height: 38, borderRadius: 'calc(var(--radius) * 0.5)', background: 'var(--surface-3)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <span style={{ width: 20, display: 'inline-flex' }}>{Icons.scale}</span>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--text)' }}>Bodyweight</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 2 }}>Daily log · {bw.length} entries</div>
          </div>
          <span style={{ fontFamily: 'var(--mono)', fontSize: 10, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'var(--dim)', display: 'flex', alignItems: 'center', gap: 5 }}>
            Change<span style={{ width: 15, display: 'inline-flex', color: 'var(--faint)' }}>{Icons.chevron}</span>
          </span>
        </button>
      </div>

      <div style={{ padding: '0 16px' }}>
        {/* chart */}
        <Card style={{ padding: '16px 8px 10px', marginBottom: 14 }}>
          <LineChart key={'bw' + unit} series={series} height={210} unit={unit} showReps={false} />
        </Card>

        {/* stats */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <Card style={{ padding: '13px 14px' }}><BwStat label="Current" value={window.fmtKg(Number(latest.weight.toFixed(1)))} unit={unit} /></Card>
          <Card style={{ padding: '13px 14px' }}><BwStat label="30-day" value={`${delta30 >= 0 ? '+' : ''}${window.fmtKg(Number(delta30.toFixed(1)))}`} unit={unit} accent /></Card>
          <Card style={{ padding: '13px 14px' }}><BwStat label="Lowest" value={window.fmtKg(Number(lowest.toFixed(1)))} unit={unit} /></Card>
        </div>

        {/* add entry */}
        <button onClick={() => setAddOpen(true)} style={{
          width: '100%', height: 50, marginBottom: 22, border: 'none', borderRadius: 'var(--radius)', background: 'var(--accent)',
          color: 'var(--accent-ink)', cursor: 'pointer', fontFamily: 'var(--display)', fontSize: 15, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, whiteSpace: 'nowrap',
        }}>
          <span style={{ width: 17, display: 'inline-flex' }}>{Icons.plus}</span>Log today’s weight
        </button>

        {/* entry log */}
        <window.SectionLabel action={<span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--dim)' }}>{bw.length} entries</span>}>History</window.SectionLabel>
        <Card pad={false} style={{ overflow: 'hidden' }}>
          {[...series].reverse().slice(0, 24).map((s, i, arr) => {
            const prev = arr[i + 1];
            const diff = prev ? s.weight - prev.weight : 0;
            return (
              <div key={s.date} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderBottom: i < arr.length - 1 ? '1px solid var(--line)' : 'none' }}>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 12, color: 'var(--dim)', width: 64, flexShrink: 0 }}>{window.fmtDate(s.date, { weekday: true })}</span>
                <span style={{ fontFamily: 'var(--mono)', fontSize: 14, fontWeight: 700, color: 'var(--text)', whiteSpace: 'nowrap' }}>{window.fmtKg(Number(s.weight.toFixed(1)))}<span style={{ fontSize: 10, color: 'var(--faint)' }}>{unit}</span></span>
                <div style={{ flex: 1 }} />
                {diff !== 0
                  ? <span style={{ fontFamily: 'var(--mono)', fontSize: 11.5, fontWeight: 600, color: diff < 0 ? 'var(--accent)' : 'var(--dim)' }}>{diff > 0 ? '+' : ''}{window.fmtKg(Number(diff.toFixed(1)))}</span>
                  : <span style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)' }}>=</span>}
              </div>
            );
          })}
        </Card>
      </div>

      <AddWeightSheet open={addOpen} onClose={() => setAddOpen(false)} onSave={onChange} />
    </div>
  );
}

Object.assign(window, { BW_ID, BodyweightProgress, AddWeightSheet });
