// screen-today.jsx — dashboard: next session, week rotation, stats, PRs, volume.
const { useState: useStateT } = React;

function SectionLabel({ children, action }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', margin: '2px 2px 10px' }}>
      <span style={{
        fontFamily: 'var(--mono)', fontSize: 11, fontWeight: 600, letterSpacing: '0.12em',
        textTransform: 'uppercase', color: 'var(--faint)',
      }}>{children}</span>
      {action}
    </div>
  );
}

function StatTile({ label, value, unit, sub, spark, sparkColor, onClick }) {
  return (
    <div onClick={onClick} style={{
      flex: 1, background: 'var(--surface)', border: '1px solid var(--line)',
      borderRadius: 'var(--radius)', padding: '13px 14px', minWidth: 0, cursor: onClick ? 'pointer' : 'default',
    }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 10, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--faint)', marginBottom: 8 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
        <span style={{ fontFamily: 'var(--display)', fontSize: 27, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', lineHeight: 1 }}>{value}</span>
        {unit && <span style={{ fontFamily: 'var(--mono)', fontSize: 12, color: 'var(--dim)' }}>{unit}</span>}
      </div>
      {spark
        ? <div style={{ marginTop: 8 }}><Sparkline values={spark} stroke={sparkColor || 'var(--accent)'} width={92} height={22} /></div>
        : <div style={{ marginTop: 6, fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--dim)' }}>{sub}</div>}
    </div>
  );
}

function WeekStrip() {
  // past week's completed sessions (newest 4 training days) + today rest
  const order = ['upper-a', 'lower-a', 'upper-b', 'lower-b'];
  const done = window.SESSIONS.slice(0, 4).map((s) => s.daySlug);
  return (
    <div style={{ display: 'flex', gap: 7 }}>
      {window.DAYS.map((d) => {
        const isDone = done.includes(d.slug);
        const isNext = d.slug === 'upper-a';
        return (
          <div key={d.slug} style={{
            flex: 1, borderRadius: 'calc(var(--radius) * 0.7)', padding: '10px 6px',
            background: isNext ? 'var(--accent)' : 'var(--surface)',
            border: `1px solid ${isNext ? 'transparent' : 'var(--line)'}`,
            textAlign: 'center', position: 'relative',
          }}>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, color: isNext ? 'var(--accent-ink)' : 'var(--faint)', opacity: isNext ? 0.7 : 1, marginBottom: 4 }}>{d.day}</div>
            <div style={{ fontFamily: 'var(--display)', fontSize: 13, fontWeight: 700, color: isNext ? 'var(--accent-ink)' : 'var(--text)' }}>{d.name.replace(' ', '')}</div>
            <div style={{ marginTop: 6, height: 14, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {isNext
                ? <span style={{ fontFamily: 'var(--mono)', fontSize: 9, fontWeight: 700, color: 'var(--accent-ink)', letterSpacing: '0.06em' }}>NEXT</span>
                : isDone
                  ? <span style={{ width: 16, height: 16, borderRadius: 99, background: 'var(--surface-3)', color: 'var(--accent)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><span style={{ width: 11, display: 'inline-flex' }}>{Icons.check}</span></span>
                  : <span style={{ width: 5, height: 5, borderRadius: 99, background: 'var(--line-strong)' }} />}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function VolumeBars() {
  const max = Math.max(...window.WEEKLY_VOLUME.map((v) => Math.max(v.sets, v.target)));
  return (
    <Card pad={false} style={{ padding: '16px 16px 8px' }}>
      {window.WEEKLY_VOLUME.map((v, i) => {
        const low = v.sets < v.target;
        return (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 11 }}>
            <span style={{ width: 74, fontSize: 12.5, color: 'var(--dim)', flexShrink: 0 }}>{v.muscle}</span>
            <div style={{ flex: 1, height: 7, background: 'var(--surface-3)', borderRadius: 99, position: 'relative', overflow: 'hidden' }}>
              <div style={{ position: 'absolute', inset: 0, width: `${(v.sets / max) * 100}%`, background: low ? 'var(--line-strong)' : 'var(--accent)', borderRadius: 99 }} />
              <div style={{ position: 'absolute', top: -3, bottom: -3, left: `${(v.target / max) * 100}%`, width: 1.5, background: 'var(--text)', opacity: 0.4 }} />
            </div>
            <span style={{ width: 38, textAlign: 'right', fontFamily: 'var(--mono)', fontSize: 11.5, color: low ? 'var(--dim)' : 'var(--text)', flexShrink: 0 }}>{v.sets}/{v.target}</span>
          </div>
        );
      })}
    </Card>
  );
}

// ── split card: one shell, internal pager above a fixed Start button ──────
function DaySlide({ day, isNext }) {
  const exCount = day.items.length;
  const lastDone = window.SESSIONS.find((s) => s.daySlug === day.slug);
  const est = Math.max(20, Math.round(exCount * 9 + 10));
  return (
    <div>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 11, fontWeight: 700, letterSpacing: '0.1em', color: 'var(--cd)', marginBottom: 10 }}>
        {isNext ? 'NEXT IN ROTATION' : `SWITCH TO · ${day.day.toUpperCase()}`}
      </div>
      <div style={{ fontFamily: 'var(--display)', fontSize: 40, fontWeight: 700, color: 'var(--ci)', letterSpacing: '-0.03em', lineHeight: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{day.name}</div>
      <div style={{ fontFamily: 'var(--display)', fontSize: 19, fontWeight: 600, color: 'var(--cd)', marginTop: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{day.focus}</div>
      <div style={{ display: 'flex', gap: 18, marginTop: 16 }}>
        {[['Exercises', exCount], ['Est. time', `~${est}m`], ['Last', lastDone ? window.daysAgo(lastDone.date) : '—']].map(([k, v], i) => (
          <div key={i}>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 16, fontWeight: 700, color: 'var(--ci)' }}>{v}</div>
            <div style={{ fontFamily: 'var(--mono)', fontSize: 9.5, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'var(--cd)', marginTop: 2 }}>{k}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function CustomSlide() {
  return (
    <div>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 11, fontWeight: 700, letterSpacing: '0.1em', color: 'var(--cd)', marginBottom: 10 }}>NO TEMPLATE</div>
      <div style={{ fontFamily: 'var(--display)', fontSize: 40, fontWeight: 700, color: 'var(--ci)', letterSpacing: '-0.03em', lineHeight: 1 }}>Custom</div>
      <div style={{ fontFamily: 'var(--display)', fontSize: 19, fontWeight: 600, color: 'var(--cd)', marginTop: 4 }}>Build it as you go</div>
      <div style={{ display: 'flex', gap: 9, marginTop: 18, alignItems: 'center', color: 'var(--cd)' }}>
        <span style={{ width: 17, display: 'inline-flex' }}>{Icons.plus}</span>
        <span style={{ fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 600 }}>Add exercises live during the session</span>
      </div>
    </div>
  );
}

function SplitCard({ onStart }) {
  const ref = React.useRef(null);
  const [idx, setIdx] = useStateT(0);
  const slides = [...window.DAYS.map((d) => ({ type: 'day', day: d })), { type: 'custom' }];
  const isCustom = slides[idx] && slides[idx].type === 'custom';

  const theme = isCustom
    ? { bg: 'var(--surface)', border: '1px dashed var(--line-strong)', ci: 'var(--text)', cd: 'var(--dim)', btnBg: 'var(--accent)', btnInk: 'var(--accent-ink)', label: 'Start empty', icon: Icons.plus }
    : { bg: 'var(--accent)', border: '1px solid transparent', ci: 'var(--accent-ink)', cd: 'color-mix(in srgb, var(--accent-ink) 58%, transparent)', btnBg: 'var(--accent-ink)', btnInk: 'var(--accent)', label: 'Start workout', icon: Icons.bolt };

  const stride = () => { const el = ref.current; return el && el.firstChild ? el.firstChild.offsetWidth : 1; };
  const onScroll = () => { const el = ref.current; if (el) setIdx(Math.round(el.scrollLeft / stride())); };
  const go = (i) => {
    const el = ref.current; if (!el) return;
    const n = Math.max(0, Math.min(slides.length - 1, i));
    el.scrollTo({ left: n * stride(), behavior: 'smooth' });
    setIdx(n);
  };
  const start = () => { const s = slides[idx]; onStart(s.type === 'day' ? s.day : null); };

  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{
        background: theme.bg, border: theme.border, borderRadius: 'var(--radius)',
        padding: 'calc(var(--pad) + 2px)', position: 'relative', overflow: 'hidden',
        transition: 'background .25s ease, border-color .25s ease',
        '--ci': theme.ci, '--cd': theme.cd,
      }}>
        {!isCustom && (
          <div style={{ position: 'absolute', right: -28, top: -28, color: 'var(--accent-ink)', opacity: 0.08, pointerEvents: 'none' }}>
            <span style={{ width: 150, display: 'inline-flex' }}>{Icons.dumbbell}</span>
          </div>
        )}
        {/* internal pager — only this region changes */}
        <div ref={ref} onScroll={onScroll} className="app-scroll" style={{
          display: 'flex', overflowX: 'auto', scrollSnapType: 'x mandatory', position: 'relative',
        }}>
          {slides.map((s, i) => (
            <div key={i} style={{ flex: '0 0 100%', scrollSnapAlign: 'start' }}>
              {s.type === 'day' ? <DaySlide day={s.day} isNext={i === 0} /> : <CustomSlide />}
            </div>
          ))}
        </div>
        {/* fixed start button */}
        <button onClick={start} style={{
          width: '100%', height: 52, marginTop: 18, border: 'none', borderRadius: 'calc(var(--radius) * 0.8)',
          background: theme.btnBg, color: theme.btnInk, cursor: 'pointer',
          fontFamily: 'var(--display)', fontSize: 17, fontWeight: 700, letterSpacing: '0.01em',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, whiteSpace: 'nowrap',
          transition: 'background .25s ease, color .25s ease',
        }}>
          <span style={{ width: 18, display: 'inline-flex' }}>{theme.icon}</span>{theme.label}
        </button>
      </div>
      {/* dots + arrows (below card, on app bg) */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, marginTop: 13 }}>
        <button onClick={() => go(idx - 1)} disabled={idx === 0} style={{ width: 28, height: 28, borderRadius: 99, border: '1px solid var(--line)', background: 'var(--surface)', color: idx === 0 ? 'var(--faint)' : 'var(--dim)', cursor: idx === 0 ? 'default' : 'pointer', opacity: idx === 0 ? 0.4 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ width: 15, display: 'inline-flex', transform: 'rotate(180deg)' }}>{Icons.chevron}</span>
        </button>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          {slides.map((s, i) => (
            <button key={i} onClick={() => go(i)} style={{
              width: i === idx ? 18 : 6, height: 6, borderRadius: 99, padding: 0, border: 'none', cursor: 'pointer',
              background: i === idx ? 'var(--accent)' : 'var(--line-strong)', transition: 'width .2s',
            }} />
          ))}
        </div>
        <button onClick={() => go(idx + 1)} disabled={idx === slides.length - 1} style={{ width: 28, height: 28, borderRadius: 99, border: '1px solid var(--line)', background: 'var(--surface)', color: idx === slides.length - 1 ? 'var(--faint)' : 'var(--dim)', cursor: idx === slides.length - 1 ? 'default' : 'pointer', opacity: idx === slides.length - 1 ? 0.4 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ width: 15, display: 'inline-flex' }}>{Icons.chevron}</span>
        </button>
      </div>
    </div>
  );
}

function TodayScreen({ onStart, onOpenExercise, onOpenProfile, profileName }) {
  const bw = window.BODYWEIGHT;
  const bwVals = bw.slice(-18).map((b) => b.weight);
  const curBw = bw[bw.length - 1].weight;
  const bwDelta = (curBw - bw[bw.length - 14].weight);
  const weekPrs = window.SESSIONS.slice(0, 4).reduce((a, s) => a + s.prCount, 0);
  const weekSets = window.WEEKLY_VOLUME.reduce((a, v) => a + v.sets, 0);

  return (
    <div style={{ padding: '0 16px' }}>
      {/* greeting */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 13, marginBottom: 18 }}>
        <button onClick={onOpenProfile} style={{ width: 46, height: 46, borderRadius: 99, background: 'var(--accent)', color: 'var(--accent-ink)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, fontFamily: 'var(--display)', fontSize: 18, fontWeight: 700 }}>{((profileName || 'A').trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('') || 'A').toUpperCase()}</button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: 'var(--mono)', fontSize: 11.5, color: 'var(--faint)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 4 }}>Sat 30 May · Rest day</div>
          <div style={{ fontFamily: 'var(--display)', fontSize: 25, fontWeight: 700, color: 'var(--text)', letterSpacing: '-0.02em', whiteSpace: 'nowrap' }}>Ready to train</div>
        </div>
      </div>

      {/* hero — swipeable split picker */}
      <SplitCard onStart={onStart} />

      {/* week rotation */}
      <SectionLabel>This week</SectionLabel>
      <div style={{ marginBottom: 22 }}><WeekStrip /></div>

      {/* stat tiles */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 22 }}>
        <StatTile label="Bodyweight" value={window.fmtWt(curBw)} unit={window.uLabel()} spark={bwVals} sparkColor="var(--dim)" onClick={() => onOpenExercise(window.BW_ID)} />
        <StatTile label="Sets / wk" value={weekSets} sub="across 11 muscles" />
        <StatTile label="PRs / wk" value={weekPrs} sub="new top sets" />
      </div>

      {/* recent PRs */}
      <SectionLabel action={<span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--dim)' }}>{window.RECENT_PRS.length}</span>}>Recent PRs</SectionLabel>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 22 }}>
        {window.RECENT_PRS.slice(0, 4).map((pr, i) => {
          const ex = window.EX[pr.exId];
          return (
            <Card key={i} onClick={() => onOpenExercise(pr.exId)} pad={false} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px' }}>
              <div style={{ width: 34, height: 34, borderRadius: 'calc(var(--radius) * 0.55)', background: 'var(--surface-3)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <span style={{ width: 18, display: 'inline-flex' }}>{Icons.bolt}</span>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ex.name}</div>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 1 }}>{window.fmtDate(pr.date, { weekday: true })}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 15, fontWeight: 700, color: 'var(--text)' }}>{window.fmtWt(pr.weight)}<span style={{ fontSize: 11, color: 'var(--dim)' }}>{window.uLabel()}</span></div>
                <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)' }}>×{pr.reps}</div>
              </div>
            </Card>
          );
        })}
      </div>

      {/* weekly volume */}
      <SectionLabel action={<span style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--dim)' }}>sets · target</span>}>Weekly volume</SectionLabel>
      <VolumeBars />
    </div>
  );
}

Object.assign(window, { TodayScreen, SectionLabel, StatTile });
