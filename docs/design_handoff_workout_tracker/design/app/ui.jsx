// ui.jsx — shared primitives, icons, and the progression chart.
// All visual tokens come from CSS variables set by the App (tweakable).
const { useState, useEffect, useRef } = React;

// ── icons (simple line glyphs) ────────────────────────────────────────────
const Icon = ({ d, size = 22, sw = 1.8, fill = 'none', style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor"
       strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" style={style}>
    {d}
  </svg>
);
const Icons = {
  home: <Icon d={<><path d="M3 10.5 12 3l9 7.5" /><path d="M5 9.5V21h14V9.5" /></>} />,
  dumbbell: <Icon d={<><path d="M6.5 6.5v11M3.5 9v6M17.5 6.5v11M20.5 9v6M6.5 12h11" /></>} />,
  chart: <Icon d={<><path d="M4 19V5M4 19h16" /><path d="M7 15l3.5-4 3 2.5L20 7" /></>} />,
  history: <Icon d={<><path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1L3 8" /><path d="M3 4v4h4M12 8v4.5l3 1.7" /></>} />,
  plus: <Icon d={<><path d="M12 5v14M5 12h14" /></>} />,
  check: <Icon d={<path d="M5 12.5l4.2 4.2L19 7" />} sw={2.2} />,
  minus: <Icon d={<path d="M5 12h14" />} sw={2.2} />,
  timer: <Icon d={<><circle cx="12" cy="13" r="8" /><path d="M12 13V9M9 2h6" /></>} />,
  chevron: <Icon d={<path d="M9 6l6 6-6 6" />} />,
  trophy: <Icon d={<><path d="M7 4h10v4a5 5 0 0 1-10 0V4Z" /><path d="M7 5H4v1.5A2.5 2.5 0 0 0 6.5 9M17 5h3v1.5A2.5 2.5 0 0 1 17.5 9M9.5 14.5 9 20h6l-.5-5.5" /></>} />,
  flame: <Icon d={<path d="M12 3c1 3-2 4-2 7a2 2 0 0 0 4 0c1 1.5 2 2.5 2 4a4 4 0 0 1-8 0c0-3 3-4 4-11Z" />} />,
  bolt: <Icon d={<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" />} fill="currentColor" sw={0} />,
  scale: <Icon d={<><path d="M12 3v3M5 7h14l-2.5 7h-9L5 7ZM7.5 14a4.5 4.5 0 0 0 9 0M9 21h6" /></>} />,
  back: <Icon d={<path d="M15 6l-6 6 6 6" />} sw={2} />,
  more: <Icon d={<><circle cx="5" cy="12" r="1.4" fill="currentColor" /><circle cx="12" cy="12" r="1.4" fill="currentColor" /><circle cx="19" cy="12" r="1.4" fill="currentColor" /></>} sw={0} />,
  edit: <Icon d={<><path d="M4 20h4L19 9l-4-4L4 16v4Z" /><path d="M14 6l4 4" /></>} />,
  target: <Icon d={<><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="3.5" /></>} />,
  gear: <Icon d={<><circle cx="12" cy="12" r="3.2" /><path d="M12 2.5v3M12 18.5v3M21.5 12h-3M5.5 12h-3M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1M18.7 18.7l-2.1-2.1M7.4 7.4 5.3 5.3" /></>} />,
  trash: <Icon d={<><path d="M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13" /></>} />,
  grip: <Icon d={<><circle cx="9" cy="6" r="1.3" fill="currentColor" /><circle cx="15" cy="6" r="1.3" fill="currentColor" /><circle cx="9" cy="12" r="1.3" fill="currentColor" /><circle cx="15" cy="12" r="1.3" fill="currentColor" /><circle cx="9" cy="18" r="1.3" fill="currentColor" /><circle cx="15" cy="18" r="1.3" fill="currentColor" /></>} sw={0} />,
  search: <Icon d={<><circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" /></>} />,
  plan: <Icon d={<><rect x="5" y="4" width="14" height="17" rx="2" /><path d="M9 4V2.8h6V4M9 10h6M9 14h6M9 18h3" /></>} />,
  user: <Icon d={<><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 3.5-6 8-6s8 2 8 6" /></>} />,
  cloud: <Icon d={<path d="M7 18a4 4 0 0 1-.4-8A6 6 0 0 1 18 9.5a3.5 3.5 0 0 1-.5 8.5H7Z" />} />,
  logout: <Icon d={<><path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 12h10M17 9l3 3-3 3" /></>} />,
  arrowUp: <Icon d={<path d="M12 19V5M6 11l6-6 6 6" />} sw={2} />,
};

// ── format helpers ────────────────────────────────────────────────────────
let _UNIT = 'kg';
function setDisplayUnit(u) { _UNIT = (u === 'lb') ? 'lb' : 'kg'; }
function uLabel() { return _UNIT; }
function fromKg(kg) { return _UNIT === 'lb' ? kg * 2.2046226 : kg; }
function toKg(v) { return _UNIT === 'lb' ? v / 2.2046226 : v; }
// plain number formatter (use for reps, generic values)
const fmtKg = (v) => (Number.isInteger(v) ? `${v}` : (Math.round(v * 10) / 10).toFixed(1).replace(/\.0$/, ''));
// weight formatter — converts kg → current display unit
function fmtWt(kg) { const v = fromKg(kg); const r = _UNIT === 'lb' ? Math.round(v) : v; return fmtKg(r); }
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function fmtDate(isoStr, opts = {}) {
  const d = new Date(isoStr + 'T00:00:00');
  const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()];
  if (opts.weekday) return `${wd} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}
function daysAgo(isoStr) {
  const d = new Date(isoStr + 'T00:00:00');
  const diff = Math.round((window.TODAY - d) / 86400000);
  if (diff <= 0) return 'today';
  if (diff === 1) return 'yesterday';
  if (diff < 7) return `${diff}d ago`;
  return `${Math.floor(diff / 7)}w ago`;
}

// muscle -> accent-tinted hue chip color (kept neutral-ish, monochrome system)
const MUSCLE_DOT = {
  chest: 'var(--accent)', back: 'var(--accent)', quads: 'var(--accent)',
};

// ── tiny building blocks ──────────────────────────────────────────────────
function Tag({ children, tone = 'mute', style }) {
  const tones = {
    accent: { bg: 'var(--accent)', col: 'var(--accent-ink)', bd: 'transparent' },
    mute: { bg: 'transparent', col: 'var(--dim)', bd: 'var(--line-strong)' },
    solid: { bg: 'var(--surface-3)', col: 'var(--text)', bd: 'transparent' },
  };
  const t = tones[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 600, letterSpacing: '0.04em',
      textTransform: 'uppercase', padding: '3px 7px', borderRadius: 'calc(var(--radius) * 0.4)',
      background: t.bg, color: t.col, border: `1px solid ${t.bd}`, whiteSpace: 'nowrap', ...style,
    }}>{children}</span>
  );
}

function PRBadge({ small }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      fontFamily: 'var(--mono)', fontSize: small ? 9.5 : 10.5, fontWeight: 700,
      letterSpacing: '0.06em', color: 'var(--accent-ink)', background: 'var(--accent)',
      padding: small ? '2px 5px' : '3px 7px', borderRadius: 'calc(var(--radius) * 0.4)',
    }}>
      <span style={{ width: small ? 9 : 11, display: 'inline-flex' }}>{Icons.bolt}</span>PR
    </span>
  );
}

// ── progression line chart (the hero view) ────────────────────────────────
function LineChart({ series, height = 200, unit = 'kg', showReps = true }) {
  const pad = { t: 18, r: 16, b: 26, l: 34 };
  const W = 360, H = height;
  const iw = W - pad.l - pad.r, ih = H - pad.t - pad.b;
  if (!series || series.length < 2) return <div style={{ height }} />;

  const weights = series.map((s) => s.weight);
  let lo = Math.min(...weights), hi = Math.max(...weights);
  const span = Math.max(hi - lo, 4);
  lo = lo - span * 0.18; hi = hi + span * 0.22;
  const x = (i) => pad.l + (i / (series.length - 1)) * iw;
  const y = (w) => pad.t + ih - ((w - lo) / (hi - lo)) * ih;

  const linePts = series.map((s, i) => `${x(i)},${y(s.weight)}`).join(' ');
  const areaPts = `${x(0)},${pad.t + ih} ${linePts} ${x(series.length - 1)},${pad.t + ih}`;

  // y gridlines (4)
  const ticks = 4;
  const grid = Array.from({ length: ticks + 1 }, (_, i) => lo + ((hi - lo) / ticks) * i);
  // x labels: month boundaries
  const xLabels = [];
  let lastM = -1;
  series.forEach((s, i) => {
    const m = new Date(s.date + 'T00:00:00').getMonth();
    if (m !== lastM) { xLabels.push({ i, label: MONTHS[m] }); lastM = m; }
  });

  const last = series[series.length - 1];
  const lastX = x(series.length - 1), lastY = y(last.weight);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: 'block', overflow: 'visible' }}>
      <defs>
        <linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.22" />
          <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
        </linearGradient>
      </defs>
      {/* gridlines */}
      {grid.map((g, i) => (
        <g key={i}>
          <line x1={pad.l} y1={y(g)} x2={W - pad.r} y2={y(g)} stroke="var(--line)" strokeWidth="1" />
          <text x={pad.l - 7} y={y(g) + 3.5} textAnchor="end"
                style={{ fontFamily: 'var(--mono)', fontSize: 9, fill: 'var(--faint)' }}>
            {Math.round(g)}
          </text>
        </g>
      ))}
      {/* area + line */}
      <polygon points={areaPts} fill="url(#areaFill)" />
      <polyline points={linePts} fill="none" stroke="var(--accent)" strokeWidth="2.4"
                strokeLinejoin="round" strokeLinecap="round" />
      {/* points + PR markers */}
      {series.map((s, i) => {
        const isLast = i === series.length - 1;
        if (s.isPr) {
          return (
            <g key={i}>
              <circle cx={x(i)} cy={y(s.weight)} r="4.5" fill="var(--accent)" stroke="var(--bg)" strokeWidth="2" />
            </g>
          );
        }
        if (isLast) return null;
        return <circle key={i} cx={x(i)} cy={y(s.weight)} r="2.2" fill="var(--accent)" opacity="0.55" />;
      })}
      {/* x labels */}
      {xLabels.map((l, i) => (
        <text key={i} x={x(l.i)} y={H - 8} textAnchor="middle"
              style={{ fontFamily: 'var(--mono)', fontSize: 9, fill: 'var(--faint)' }}>{l.label}</text>
      ))}
      {/* last point emphasized */}
      <circle cx={lastX} cy={lastY} r="9" fill="var(--accent)" opacity="0.16" />
      <circle cx={lastX} cy={lastY} r="4.5" fill="var(--accent)" stroke="var(--bg)" strokeWidth="2" />
      <g transform={`translate(${Math.min(lastX, W - 58)}, ${Math.max(lastY - 26, 4)})`}>
        <text style={{ fontFamily: 'var(--mono)', fontSize: 12, fontWeight: 700, fill: 'var(--text)' }}>
          {fmtKg(last.weight)}{unit}{showReps ? ` ×${last.reps}` : ''}
        </text>
      </g>
    </svg>
  );
}

// ── sparkline (mini trend) ────────────────────────────────────────────────
function Sparkline({ values, width = 64, height = 24, stroke = 'var(--accent)' }) {
  if (!values || values.length < 2) return null;
  const lo = Math.min(...values), hi = Math.max(...values);
  const sp = Math.max(hi - lo, 0.001);
  const x = (i) => (i / (values.length - 1)) * width;
  const y = (v) => height - 2 - ((v - lo) / sp) * (height - 4);
  const pts = values.map((v, i) => `${x(i)},${y(v)}`).join(' ');
  return (
    <svg width={width} height={height} style={{ display: 'block', overflow: 'visible' }}>
      <polyline points={pts} fill="none" stroke={stroke} strokeWidth="1.8" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={x(values.length - 1)} cy={y(values[values.length - 1])} r="2" fill={stroke} />
    </svg>
  );
}

// ── card ──────────────────────────────────────────────────────────────────
function Card({ children, style, onClick, pad = true }) {
  return (
    <div onClick={onClick} style={{
      background: 'var(--surface)', borderRadius: 'var(--radius)',
      border: '1px solid var(--line)', padding: pad ? 'var(--pad)' : 0,
      ...(onClick ? { cursor: 'pointer' } : {}), ...style,
    }}>{children}</div>
  );
}

Object.assign(window, {
  Icons, Icon, fmtKg, fmtWt, fromKg, toKg, uLabel, setDisplayUnit, fmtDate, daysAgo, MONTHS, Tag, PRBadge, LineChart, Sparkline, Card,
});
