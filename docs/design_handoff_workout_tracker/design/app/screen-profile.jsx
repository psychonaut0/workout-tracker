// screen-profile.jsx — Profile & app settings: account, units, appearance, sync.
const { useState: useStateProf } = React;

function Row({ icon, title, sub, right, onClick, danger }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 13, padding: '13px 14px',
      cursor: onClick ? 'pointer' : 'default',
    }}>
      {icon && (
        <div style={{ width: 34, height: 34, borderRadius: 'calc(var(--radius) * 0.5)', background: 'var(--surface-3)', color: danger ? '#ff6b5e' : 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <span style={{ width: 18, display: 'inline-flex' }}>{icon}</span>
        </div>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, fontWeight: 600, color: danger ? '#ff6b5e' : 'var(--text)' }}>{title}</div>
        {sub && <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</div>}
      </div>
      {right}
    </div>
  );
}

function Group({ label, children }) {
  return (
    <div style={{ marginBottom: 20 }}>
      <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, fontWeight: 600, letterSpacing: '0.1em', textTransform: 'uppercase', color: 'var(--faint)', margin: '0 2px 9px' }}>{label}</div>
      <div style={{ background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'var(--radius)', overflow: 'hidden' }}>
        {React.Children.toArray(children).filter(Boolean).map((c, i, arr) => (
          <div key={i} style={{ borderBottom: i < arr.length - 1 ? '1px solid var(--line)' : 'none' }}>{c}</div>
        ))}
      </div>
    </div>
  );
}

function ProfileScreen({ onClose, settings, onSet }) {
  const { Toggle } = window;
  const [name, setName] = useStateProf(settings.name);
  const [server, setServer] = useStateProf(settings.server);
  const [editing, setEditing] = useStateProf(false);

  const initials = (name.trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('') || 'A').toUpperCase();
  const sessions = window.SESSIONS.length;
  const prs = window.SESSIONS.reduce((a, s) => a + s.prCount, 0);
  const bw = window.BODYWEIGHT[window.BODYWEIGHT.length - 1].weight;
  const accents = ['#c2f53a', '#5ce6a4', '#ffc24b', '#5cc8ff'];

  return (
    <div style={{ flex: 1, minHeight: 0, background: 'var(--bg)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 56, flexShrink: 0, background: 'var(--bg)', borderBottom: '1px solid var(--line)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '4px 16px 12px' }}>
          <button onClick={onClose} style={{ width: 36, height: 36, borderRadius: 99, border: '1px solid var(--line)', background: 'var(--surface)', color: 'var(--dim)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <span style={{ width: 18, display: 'inline-flex', transform: 'rotate(180deg)' }}>{Icons.chevron}</span>
          </button>
          <div style={{ flex: 1, fontFamily: 'var(--display)', fontSize: 19, fontWeight: 700, color: 'var(--text)' }}>Profile</div>
        </div>
      </div>

      <div className="app-scroll" style={{ flex: 1, overflowY: 'auto', padding: '18px 16px 104px' }}>
        {/* profile header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 15, marginBottom: 18 }}>
          <div style={{ width: 66, height: 66, borderRadius: 99, background: 'var(--accent)', color: 'var(--accent-ink)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, fontFamily: 'var(--display)', fontSize: 26, fontWeight: 700 }}>{initials}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            {editing ? (
              <input value={name} onChange={(e) => setName(e.target.value)} autoFocus
                onBlur={() => { setEditing(false); onSet({ name }); }}
                onKeyDown={(e) => { if (e.key === 'Enter') { setEditing(false); onSet({ name }); } }}
                style={{ width: '100%', background: 'var(--surface-3)', border: '1px solid var(--line-strong)', borderRadius: 'calc(var(--radius) * 0.5)', color: 'var(--text)', fontFamily: 'var(--display)', fontSize: 22, fontWeight: 700, padding: '4px 10px', outline: 'none', boxSizing: 'border-box' }} />
            ) : (
              <div onClick={() => setEditing(true)} style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                <span style={{ fontFamily: 'var(--display)', fontSize: 23, fontWeight: 700, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</span>
                <span style={{ width: 15, display: 'inline-flex', color: 'var(--faint)', flexShrink: 0 }}>{Icons.edit}</span>
              </div>
            )}
            <div style={{ fontFamily: 'var(--mono)', fontSize: 11, color: 'var(--faint)', marginTop: 3 }}>Training since Mar 2026 · 4-day split</div>
          </div>
        </div>

        {/* quick stats */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 22 }}>
          {[['Sessions', sessions], ['PRs', prs], ['Bodyweight', `${window.fmtWt(bw)}${window.uLabel()}`]].map(([k, v], i) => (
            <div key={i} style={{ flex: 1, background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 'var(--radius)', padding: '12px 10px', textAlign: 'center' }}>
              <div style={{ fontFamily: 'var(--display)', fontSize: 20, fontWeight: 700, color: 'var(--text)', lineHeight: 1 }}>{v}</div>
              <div style={{ fontFamily: 'var(--mono)', fontSize: 9, letterSpacing: '0.06em', textTransform: 'uppercase', color: 'var(--faint)', marginTop: 6 }}>{k}</div>
            </div>
          ))}
        </div>

        {/* units */}
        <Group label="Units">
          <Row icon={Icons.scale} title="Weight unit" sub="Applies everywhere"
            right={<window.ChipSelect value={settings.unit} options={[['kg', 'kg'], ['lb', 'lb']]} onChange={(v) => onSet({ unit: v })} />} />
        </Group>

        {/* appearance */}
        <Group label="Appearance">
          <Row icon={settings.mode === 'dark' ? Icons.flame : Icons.bolt} title="Theme"
            right={<window.ChipSelect value={settings.mode} options={[['dark', 'Dark'], ['light', 'Light']]} onChange={(v) => onSet({ mode: v })} />} />
          <Row icon={Icons.target} title="Accent" sub="App highlight color"
            right={(
              <div style={{ display: 'flex', gap: 7 }}>
                {accents.map((c) => (
                  <button key={c} onClick={() => onSet({ accent: c })} style={{
                    width: 26, height: 26, borderRadius: 99, cursor: 'pointer', padding: 0,
                    background: c, border: settings.accent === c ? '2px solid var(--text)' : '2px solid transparent',
                    boxShadow: settings.accent === c ? '0 0 0 2px var(--bg) inset' : 'none',
                  }} />
                ))}
              </div>
            )} />
        </Group>

        {/* sync — PowerSync-style local-first backend from the repo */}
        <Group label="Sync & Backend">
          <Row icon={Icons.cloud} title="Sync server"
            sub={server}
            right={<span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><span style={{ width: 7, height: 7, borderRadius: 99, background: 'var(--accent)' }} /><span style={{ fontFamily: 'var(--mono)', fontSize: 11, fontWeight: 600, color: 'var(--dim)' }}>Connected</span></span>} />
          <div style={{ padding: '0 14px 13px' }}>
            <window.TextInput value={server} onChange={setServer} placeholder="https://sync.example.dev" />
            <div style={{ fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 7 }}>Local-first · last synced 2m ago · 6 tables</div>
          </div>
        </Group>

        {/* account */}
        <Group label="Account">
          <Row icon={Icons.user} title="Signed in" sub={`${name.toLowerCase().replace(/\s+/g, '.')}@workout.app`} />
          <Row icon={Icons.logout} title="Sign out" danger onClick={() => {}} />
        </Group>

        <div style={{ textAlign: 'center', fontFamily: 'var(--mono)', fontSize: 10.5, color: 'var(--faint)', marginTop: 4 }}>workout-tracker · v1.0.0</div>
      </div>
    </div>
  );
}

Object.assign(window, { ProfileScreen });
