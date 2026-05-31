// screen-history.jsx — past sessions grouped by week, expandable to top sets.
const { useState: useStateH } = React;

function SessionCard({ session }) {
  const [open, setOpen] = useStateH(false);
  const tmpl = window.DAY[session.daySlug];
  const topSets = session.exercises.filter((e) => !window.EX[e.exerciseId].compound ? false : true);
  return (
    <div style={{ background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'var(--radius)', overflow: 'hidden', marginBottom: 9 }}>
      <div onClick={() => setOpen(!open)} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 14px', cursor: 'pointer' }}>
        <div style={{ width: 44, flexShrink: 0, textAlign: 'center' }}>
          <div style={{ fontFamily: 'var(--display)', fontSize: 20, fontWeight: 700, color: 'var(--text)', lineHeight: 1 }}>{new Date(session.date + 'T00:00:00').getDate()}</div>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: 'var(--faint)', textTransform: 'uppercase', marginTop: 2 }}>{window.MONTHS[new Date(session.date + 'T00:00:00').getMonth()]}</div>
        </div>
        <div style={{ width: 1, alignSelf: 'stretch', background: 'var(--line)' }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14.5, fontWeight: 600, color: 'var(--text)' }}>{tmpl.name} <span style={{ color: 'var(--faint)', fontWeight: 500 }}>· {tmpl.focus}</span></div>
          <div style={{ display: 'flex', gap: 12, marginTop: 4, fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)' }}>
            <span>{session.exercises.length} ex</span>
            <span>{session.durationMin}m</span>
            <span>{window.daysAgo(session.date)}</span>
          </div>
        </div>
        {session.prCount > 0 && <PRBadge small />}
        <span style={{ width: 16, display: 'inline-flex', color: 'var(--faint)', transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>{Icons.chevron}</span>
      </div>
      {open && (
        <div style={{ padding: '0 14px 12px' }}>
          <div style={{ borderTop: '1px solid var(--line)', paddingTop: 8 }}>
            {session.exercises.map((e, i) => {
              const ex = window.EX[e.exerciseId];
              return (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0' }}>
                  <span style={{ width: 5, height: 5, borderRadius: 99, background: ex.compound ? 'var(--accent)' : 'var(--line-strong)', flexShrink: 0 }} />
                  <span style={{ flex: 1, fontSize: 13, color: 'var(--dim)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</span>
                  {e.isPr && <span style={{ width: 13, display: 'inline-flex', color: 'var(--accent)' }}>{Icons.bolt}</span>}
                  <span style={{ fontFamily: 'var(--mono)', fontSize: 12.5, fontWeight: 700, color: 'var(--text)' }}>{window.fmtWt(e.topWeight)}<span style={{ fontSize: 9.5, color: 'var(--faint)' }}>{window.uLabel()}</span> <span style={{ color: 'var(--faint)', fontWeight: 400 }}>×{e.topReps}</span></span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function HistoryScreen() {
  // group sessions by ISO week label
  const groups = {};
  window.SESSIONS.forEach((s) => {
    const d = new Date(s.date + 'T00:00:00');
    const monday = new Date(d); monday.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    const key = window.iso(monday);
    (groups[key] = groups[key] || []).push(s);
  });
  const weekKeys = Object.keys(groups).sort((a, b) => (a < b ? 1 : -1));

  const monthSessions = window.SESSIONS.filter((s) => new Date(s.date + 'T00:00:00') >= window.addDays(window.TODAY, -28));
  const monthPrs = monthSessions.reduce((a, s) => a + s.prCount, 0);
  const totalTonnage = monthSessions.reduce((a, s) => a + s.exercises.reduce((b, e) => b + e.topWeight * e.topReps, 0), 0);

  return (
    <div style={{ padding: '0 16px' }}>
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 5 }}>{window.SESSIONS.length} sessions logged</div>
        <div style={{ fontFamily: 'var(--display)', fontSize: 28, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em' }}>History</div>
      </div>

      {/* 4-week summary */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 24 }}>
        {[['Sessions', monthSessions.length], ['PRs', monthPrs], ['Volume', `${(window.fromKg(totalTonnage) / 1000).toFixed(1)}${window.uLabel() === 'kg' ? 't' : 'k'}`]].map(([k, v], i) => (
          <div key={i} style={{ flex: 1, background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'var(--radius)', padding: '12px 14px' }}>
            <div style={{ fontFamily: 'var(--display)', fontSize: 23, fontWeight: 700, color: 'var(--text)', lineHeight: 1 }}>{v}</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.07em', textTransform: 'uppercase', color: 'var(--faint)', marginTop: 6 }}>{k} · 4wk</div>
          </div>
        ))}
      </div>

      {weekKeys.map((wk) => {
        const label = `Week of ${window.fmtDate(wk)}`;
        const sess = groups[wk];
        const prs = sess.reduce((a, s) => a + s.prCount, 0);
        return (
          <div key={wk} style={{ marginBottom: 18 }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', margin: '0 2px 10px' }}>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 11, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--faint)' }}>{label}</span>
              <span style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--dim)' }}>{sess.length} sessions{prs ? ` · ${prs} PR` : ''}</span>
            </div>
            {sess.map((s) => <SessionCard key={s.id} session={s} />)}
          </div>
        );
      })}
    </div>
  );
}

Object.assign(window, { HistoryScreen });
