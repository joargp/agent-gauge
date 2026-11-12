// Agent Gauge: the shared engine for every design direction.
// It holds the copy, the simulated readings, the markup and the moments. Each direction's
// css styles the same DOM. Mockup only, not production code.
//
// The copy, formatting and thresholds mirror the shipping app (0.1.4):
// Sources/AgentGauge/Views/*.swift, Support/GaugeProvider.swift, GaugeCore/Support/*.swift.

/* ---------- simulated clock: Thu 12 Nov 2026, 10:06 ---------- */
const NOW = new Date(2026, 10, 12, 10, 6, 0);
const MIN = 60_000;

/* ---------- copy, per agent (GaugeProvider.swift) ---------- */
const AGENTS = {
  claude: {
    name: 'Claude',
    icon: 'sparkles',
    fiveTint: 'var(--claude-five)',
    weeklyTint: 'var(--claude-weekly)',
    accent: 'var(--claude-five)',
    privacy: 'No credentials. Reads a local cache written by your Claude status line.',
    awaiting: 'Awaiting first capture',
    refreshHint: 'Start Claude Code to refresh',
    staleHint: 'start Claude Code to refresh',
    ageAsCapture: true,
  },
  codex: {
    name: 'Codex',
    icon: 'gauge',
    fiveTint: 'var(--codex-five)',
    weeklyTint: 'var(--codex-weekly)',
    accent: 'var(--codex-weekly)',
    privacy: 'Uses your local Codex login. Credentials stay with Codex.',
    awaiting: 'Waiting for Codex',
    refreshHint: 'Refresh to update',
    staleHint: 'Codex isn’t responding',
    ageAsCapture: false,
  },
};

/* ---------- state: everything Reset goes back to ----------
   A window is { used: percent used, resetIn: minutes from NOW } or null.
   resetIn <= 0 means the reset time passed without a newer reading. */
const initial = () => ({
  open: null, // 'claude' | 'codex' | null
  menu: false, // settings menu in the open popover
  visible: { claude: true, codex: true },
  launchAtLogin: true,
  // Built-in updates: only rendered where <body data-updates="on">.
  version: '0.1.5',
  updateMode: 'download', // off | check | download
  update: { phase: 'idle', progress: 0, notes: false },
  nextCheck: 'uptodate', // what "Check for Updates…" finds: uptodate | found | error
  claude: {
    usage: {
      five: { used: 25, resetIn: 134 }, // 12:20
      weekly: { used: 72, resetIn: 594 }, // 20:00
      ageSec: 20,
      badge: 'Claude Code 2.1.322',
      absentMeansNoLimit: false,
      // Fable's own weekly cap ("up to 50% of your weekly limit"). Only shown where
      // <body data-fable="on">; older revisions ignore it.
      fable: { used: 70, resetIn: 594 },
    },
    setup: null,
    error: null,
    refreshing: false,
  },
  codex: {
    usage: {
      five: null,
      weekly: { used: 53, resetIn: 6 * 1440 + 22 * 60 + 7 }, // Nov 19 at 08:13
      ageSec: 15,
      badge: 'Pro Lite',
      absentMeansNoLimit: true,
    },
    setup: null,
    error: null,
    refreshing: false,
  },
});

/* ---------- GaugeCore logic ---------- */
function windowState(usage, key) {
  if (!usage) return { kind: 'awaiting' };
  const w = usage[key];
  if (!w) return { kind: usage.absentMeansNoLimit ? 'nolimit' : 'awaiting' };
  if (w.resetIn <= 0) return { kind: 'rolled' };
  return { kind: 'present', left: Math.min(100, Math.max(0, 100 - w.used)), resetIn: w.resetIn };
}

function freshness(usage) {
  if (!usage) return null;
  if (usage.ageSec <= 120) return 'live';
  if (usage.ageSec <= 3600) return 'recent';
  return 'stale';
}

function resetDescription(minutes) {
  if (minutes <= 0) return 'Resetting now';
  const d = Math.floor(minutes / 1440);
  const h = Math.floor((minutes % 1440) / 60);
  const m = Math.floor(minutes % 60);
  if (d > 0) return h > 0 ? `Resets in ${d}d ${h}h` : `Resets in ${d}d`;
  if (h > 0) return m > 0 ? `Resets in ${h}h ${m}m` : `Resets in ${h}h`;
  return `Resets in ${Math.max(1, m)}m`;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function resetDate(minutes) {
  const t = new Date(NOW.getTime() + minutes * MIN);
  const hh = String(t.getHours()).padStart(2, '0');
  const mm = String(t.getMinutes()).padStart(2, '0');
  return `${MONTHS[t.getMonth()]} ${t.getDate()} at ${hh}:${mm}`;
}

function ageDescription(ageSec, prefix) {
  if (ageSec == null) return 'Not captured yet';
  if (ageSec < 60) return `${prefix} just now`;
  if (ageSec < 3600) return `${prefix} ${Math.floor(ageSec / 60)}m ago`;
  if (ageSec < 86400) return `${prefix} ${Math.floor(ageSec / 3600)}h ago`;
  return `${prefix} ${Math.floor(ageSec / 86400)}d ago`;
}

// GaugePalette.ringColor
function ringColor(st, healthy) {
  if (st.kind !== 'present') return 'var(--ring-unknown)';
  if (st.left <= 10) return 'var(--critical)';
  if (st.left <= 25) return 'var(--low)';
  return healthy;
}

/* ---------- ring drawing (RingGeometry.swift) ---------- */
function ring({ frame, r, line, st, tint, arcOnlyWhenPresent = false, cls = '' }) {
  const raw = st.kind === 'present' ? st.left / 100 : 0;
  const cap = line / (2 * Math.PI * r);
  const rounded = raw > 0 && raw < 1 && raw > cap;
  const p = rounded ? raw - cap : raw;
  const C = 2 * Math.PI * r;
  const pad = line / 2;
  const size = frame + 2 * pad;
  const c = size / 2;
  const showArc = !(arcOnlyWhenPresent && st.kind !== 'present') && p > 0;
  return `<svg class="ring ${cls}" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" style="margin:${-pad}px" aria-hidden="true">
    <circle class="track" cx="${c}" cy="${c}" r="${r}" fill="none" stroke-width="${line}"/>
    ${showArc ? `<circle class="arc" cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${ringColor(st, tint)}" stroke-width="${line}"
      stroke-linecap="${rounded ? 'round' : 'butt'}" stroke-dasharray="${p * C} ${C}" transform="rotate(-90 ${c} ${c})"/>` : ''}
  </svg>`;
}

/* ---------- icons (stand-ins for the SF Symbols the app uses) ---------- */
const ICONS = {
  sparkles: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M13 6c.6 4 2.4 5.9 6.5 6.5-4.1.6-5.9 2.5-6.5 6.5-.6-4-2.4-5.9-6.5-6.5C10.6 11.9 12.4 10 13 6Z"/><path fill="currentColor" d="M6 2.5c.3 1.9 1.1 2.7 3 3-1.9.3-2.7 1.1-3 3-.3-1.9-1.1-2.7-3-3 1.9-.3 2.7-1.1 3-3ZM18.5 1.5c.2 1.2.8 1.8 2 2-1.2.2-1.8.8-2 2-.2-1.2-.8-1.8-2-2 1.2-.2 1.8-.8 2-2Z"/></svg>`,
  gauge: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="9.2"/><path d="M12 6.2v1.6M6.9 8.4l1.1 1.1M17.1 8.4 16 9.5M5.6 13.3h1.6M16.8 13.3h1.6"/><path d="m12 13.3 2.6-4.1" stroke-width="2"/><circle cx="12" cy="13.3" r="1.2" fill="currentColor" stroke="none"/></svg>`,
  lock: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M12 2.8 4.6 5.6v5.7c0 4.6 3.1 8.4 7.4 9.9 4.3-1.5 7.4-5.3 7.4-9.9V5.6Z"/><rect x="9" y="11" width="6" height="4.6" rx=".8" fill="currentColor" stroke="none"/><path d="M10.2 11V9.6a1.8 1.8 0 0 1 3.6 0V11"/></svg>`,
  refresh: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M18 2.8v4.4h-4.4"/></svg>`,
  gear: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M10.3 2.8h3.4l.5 2.5 1.6.9 2.4-.9 1.7 2.9-1.9 1.7v1.9l1.9 1.7-1.7 2.9-2.4-.9-1.6.9-.5 2.5h-3.4l-.5-2.5-1.6-.9-2.4.9-1.7-2.9 1.9-1.7V9.9L4.1 8.2l1.7-2.9 2.4.9 1.6-.9Z" stroke-linejoin="round"/><circle cx="12" cy="12" r="3"/></svg>`,
  wrench: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a4 4 0 0 0 5 5L13 18a2.1 2.1 0 0 1-3-3Z"/><path d="m4 20 5-5"/></svg>`,
  warn: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M10.3 3.6a2 2 0 0 1 3.4 0l8 13.9a2 2 0 0 1-1.7 3H4a2 2 0 0 1-1.7-3Z"/><path d="M12 9v5" stroke="#000" stroke-opacity=".75" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17" r="1.1" fill="#000" fill-opacity=".75"/></svg>`,
  check: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>`,
  apple: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M16.4 12.6c0-2.4 2-3.5 2-3.6-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.2-2.8.8-3.5.8-.7 0-1.8-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.5 1.3-2.6 0 0-2.5-1-2.5-3.6ZM14.1 5.6c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.8 1 .1 2.1-.5 2.7-1.2Z"/></svg>`,
  wifi: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.2 9.2 0 0 1 12.4 0M9.1 15.8a4.4 4.4 0 0 1 5.8 0"/><circle cx="12" cy="19.2" r="1.3" fill="currentColor" stroke="none"/></svg>`,
  battery: `<svg viewBox="0 0 30 24" aria-hidden="true"><rect x="1.5" y="6.5" width="23" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="3.2" y="8.2" width="15.5" height="7.6" rx="1.6" fill="currentColor"/><path d="M26.3 10v4" stroke="currentColor" stroke-opacity=".5" stroke-width="1.6" stroke-linecap="round"/></svg>`,
  control: `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="5" width="18" height="5.5" rx="2.75"/><rect x="3" y="13.5" width="18" height="5.5" rx="2.75"/><circle cx="15.8" cy="7.75" r="1.6" fill="currentColor"/><circle cx="8.2" cy="16.25" r="1.6" fill="currentColor"/></svg>`,
};

/* ---------- markup: the Mac desktop, its menu bar, and the popover ---------- */
const markup = () => `
  <div class="desktop" data-region="desktop">
    <header class="menubar" data-region="menubar">
      <div class="menus">
        <span class="apple">${ICONS.apple}</span>
        <b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span>
      </div>
      <div class="extras">
        <button class="status-item" data-agent="claude" id="si-claude"></button>
        <button class="status-item" data-agent="codex" id="si-codex"></button>
        <span class="sys">${ICONS.battery}</span>
        <span class="sys">${ICONS.wifi}</span>
        <span class="sys">${ICONS.control}</span>
        <span class="clock">Thu 12 Nov&nbsp; 10:06</span>
      </div>
    </header>
    <section class="popover" id="popover" data-region="popover" role="dialog" hidden></section>
  </div>`;

/* ---------- render ---------- */
function statusItem(agent) {
  const a = AGENTS[agent];
  const s = state[agent];
  const five = windowState(s.usage, 'five');
  const weekly = windowState(s.usage, 'weekly');
  return `<span class="nested-rings">
    ${ring({ frame: 15.3, r: 7.65, line: 2, st: weekly, tint: a.weeklyTint, arcOnlyWhenPresent: true, cls: 'outer' })}
    ${ring({ frame: 9.36, r: 4.68, line: 2, st: five, tint: a.fiveTint, arcOnlyWhenPresent: true, cls: 'inner' })}
  </span>`;
}

function ringBlock(agent, title, key) {
  const a = AGENTS[agent];
  const st = windowState(state[agent].usage, key);
  const tint = key === 'five' ? a.fiveTint : a.weeklyTint;
  let caption, detail;
  if (st.kind === 'present') {
    caption = resetDescription(st.resetIn);
    detail = resetDate(st.resetIn);
  } else if (st.kind === 'rolled') {
    caption = 'No recent data';
    detail = a.refreshHint;
  } else if (st.kind === 'awaiting') {
    caption = a.awaiting;
    detail = a.refreshHint;
  } else {
    caption = 'No limit on this plan';
    detail = null;
  }
  const center =
    st.kind === 'present'
      ? `<span class="pct">${Math.round(st.left)}%</span><span class="left">left</span>`
      : `<span class="pct none">—</span>`;
  return `<div class="usage-ring" data-kind="${st.kind}">
    <div class="dial">${ring({ frame: 104, r: 52, line: 10, st, tint })}<div class="center">${center}</div></div>
    <div class="window-title">${title}</div>
    <div class="caption">${caption}</div>
    ${detail ? `<div class="detail">${detail}</div>` : ''}
  </div>`;
}

/* ---------- Fable sub-limit (revision current2, gated by <body data-fable="on">) ---------- */
const FABLE = document.body.dataset.fable === 'on';

function fableRow(agent) {
  const usage = state[agent].usage;
  if (agent !== 'claude' || !usage?.fable) return '';
  const st = windowState(usage, 'fable');
  const color = ringColor(st, AGENTS[agent].weeklyTint);
  const left = st.kind === 'present' ? Math.round(st.left) : null;
  const weekly = windowState(usage, 'weekly');
  const first = left != null && weekly.kind === 'present' && left < Math.round(weekly.left);
  return `<div class="sublimit" data-kind="${st.kind}" ${first ? 'data-first' : ''}>
    <div class="sub-head"><strong>Fable</strong><span class="sub-pct">${left != null ? `${left}% left` : '—'}</span></div>
    <div class="bar"><span style="width:${left ?? 0}%;background:${color}"></span></div>
    <div class="sub-caption">Up to 50% of your weekly limit · ${
      st.kind === 'present' ? resetDescription(st.resetIn).replace('Resets', 'resets') : 'no recent data'
    }</div>
    ${first ? '<div class="sub-note">Fable runs out before your weekly limit. Other models keep working.</div>' : ''}
  </div>`;
}

function popover(agent) {
  const a = AGENTS[agent];
  const s = state[agent];
  const f = freshness(s.usage);
  const age =
    f === 'stale' && a.ageAsCapture
      ? ageDescription(s.usage?.ageSec, 'Last capture')
      : ageDescription(s.usage?.ageSec, 'Updated');
  const others = Object.keys(AGENTS).filter((k) => state.visible[k]).length;
  return `
    <div class="pop-header">
      <span class="agent-icon" style="color:${a.accent}">${ICONS[a.icon]}</span>
      <div class="pop-title"><strong>${a.name}</strong><span>Subscription usage</span></div>
      ${s.usage?.badge ? `<span class="badge">${s.usage.badge}</span>` : ''}
    </div>
    <div class="rings">
      ${ringBlock(agent, '5 hours', 'five')}
      ${ringBlock(agent, 'Weekly', 'weekly')}
    </div>
    ${FABLE ? fableRow(agent) : ''}
    <div class="data-age" data-fresh="${f ?? 'none'}">
      <span class="dot"></span><span>${age}</span>
      ${f === 'stale' ? `<span class="stale-hint">· ${a.staleHint}</span>` : ''}
      ${s.refreshing ? '<span class="spinner" aria-label="Refreshing"></span>' : ''}
    </div>
    ${s.setup ? `<div class="notice setup">${ICONS.wrench}<span>${s.setup}</span></div>` : ''}
    ${s.error ? `<div class="notice error">${ICONS.warn}<span>${s.error}</span></div>` : ''}
    ${UPDATES ? updateRow() : ''}
    <hr>
    <div class="privacy">${ICONS.lock}<span>${a.privacy}</span></div>
    <div class="pop-actions">
      <button class="btn refresh" ${s.refreshing ? 'disabled' : ''}>${ICONS.refresh}<span>Refresh</span></button>
      <span class="spacer"></span>
      <span class="menu-anchor">
        <button class="gear" aria-label="Settings" aria-expanded="${state.menu}">${ICONS.gear}</button>
        ${
          state.menu
            ? `<div class="menu" role="menu">
            ${Object.entries(AGENTS)
              .map(
                ([k, ag]) =>
                  `<button role="menuitemcheckbox" class="mi toggle-visible" data-agent="${k}" ${state.visible[k] && others <= 1 ? 'disabled' : ''}>
                    <span class="tick">${state.visible[k] ? ICONS.check : ''}</span>Show ${ag.name}</button>`,
              )
              .join('')}
            <div class="sep"></div>
            ${UPDATES ? updateMenuItems() : ''}
            <button role="menuitem" class="mi welcome"><span class="tick"></span>Welcome…</button>
            <button role="menuitemcheckbox" class="mi launch"><span class="tick">${state.launchAtLogin ? ICONS.check : ''}</span>Launch at Login</button>
          </div>`
            : ''
        }
      </span>
      <button class="btn quit">Quit</button>
    </div>`;
}

function renderProduct(device) {
  device.dataset.open = state.open ?? '';
  for (const k of Object.keys(AGENTS)) {
    const el = $(`#si-${k}`);
    el.hidden = !state.visible[k];
    el.classList.toggle('active', state.open === k);
    el.setAttribute('aria-label', `${AGENTS[k].name} usage`);
    el.innerHTML = statusItem(k);
  }
  if (UPDATES) {
    // One dot, on the first visible icon, while an update waits for the person.
    const first = Object.keys(AGENTS).find((k) => state.visible[k]);
    const dot = ['available', 'ready'].includes(state.update.phase);
    for (const k of Object.keys(AGENTS)) $(`#si-${k}`).classList.toggle('has-update', dot && k === first);
  }
  const pop = $('#popover');
  if (!state.open || !state.visible[state.open]) {
    pop.hidden = true;
    pop.innerHTML = '';
    return;
  }
  pop.hidden = false;
  pop.dataset.agent = state.open;
  pop.innerHTML = popover(state.open);
  // Drop the popover under its status item, like a MenuBarExtra window.
  const item = $(`#si-${state.open}`).getBoundingClientRect();
  const desk = $('.desktop').getBoundingClientRect();
  const left = Math.min(item.left - desk.left + item.width / 2 - pop.offsetWidth / 2, desk.width - pop.offsetWidth - 8);
  pop.style.left = `${Math.max(8, left)}px`;
}

/* ---------- flows ---------- */
function openOnly(agent) {
  state.open = agent;
  state.menu = false;
  render();
}

async function refreshFlow(agent = state.open) {
  if (!agent) return;
  const s = state[agent];
  if (s.refreshing) return;
  s.refreshing = true;
  render();
  await sleep(agent === 'codex' ? 1400 : 700);
  s.refreshing = false;
  // Claude re-reads the same cache: nothing newer arrives until a Claude Code session renders
  // its status line. Codex asks the CLI again, so its reading is new and any error clears.
  if (agent === 'codex' && s.usage) {
    s.error = null;
    s.usage.ageSec = 1;
  }
  render();
}

function moment(fn) {
  return () => {
    reset();
    fn();
    render();
  };
}

/* ---------- built-in updates (revision current3, gated by <body data-updates="on">) ----------
   Mirrors Sparkle's driver states as Ghostty's UpdateDriver lists them. */
const UPDATES = document.body.dataset.updates === 'on';
const VERSION = '0.1.5';
const NEXT = '0.1.6';
const NOTES = [
  'Shows Fable’s own weekly limit for Claude.',
  'Updates itself. This is the first version that can.',
  'Fixes the Codex ring staying grey after waking from sleep.',
];
const MODES = {
  off: 'Off',
  check: 'Notify me',
  download: 'Download, install on quit',
};

function updateRow() {
  const u = state.update;
  const ver = state.version;
  const notes = u.notes
    ? `<ul class="notes">${NOTES.map((n) => `<li>${n}</li>`).join('')}</ul><button class="link skip">Skip this version</button>`
    : '';
  const what = `<button class="link toggle-notes" aria-expanded="${u.notes}">${u.notes ? 'Hide changes' : 'What’s new'}</button>`;
  const rows = {
    checking: [`<span class="spinner"></span>`, 'Checking for updates…', '', ''],
    uptodate: [ICONS.check, `Agent Gauge ${ver} is the latest version.`, '', ''],
    available: [
      '<span class="up-dot"></span>',
      `Agent Gauge ${NEXT} is available`,
      `You have ${ver}. ${what}`,
      `<button class="btn later">Later</button><button class="btn primary install">Install</button>`,
    ],
    downloading: [
      '<span class="spinner"></span>',
      `Downloading ${NEXT}`,
      `<span class="bar up-bar"><span style="width:${u.progress}%"></span></span><span class="up-pct">${u.progress}%</span>`,
      `<button class="btn cancel">Cancel</button>`,
    ],
    extracting: ['<span class="spinner"></span>', `Preparing ${NEXT}…`, '', ''],
    ready: [
      '<span class="up-dot"></span>',
      `Agent Gauge ${NEXT} is ready`,
      `Installs when you quit. ${what}`,
      `<button class="btn primary restart">Restart Now</button>`,
    ],
    installing: ['<span class="spinner"></span>', `Installing ${NEXT}…`, 'Agent Gauge will open again in a moment.', ''],
    error: [
      ICONS.warn,
      'Couldn’t check for updates',
      'GitHub didn’t answer. You may be offline. Nothing was changed.',
      `<button class="btn retry-update">Try Again</button>`,
    ],
  }[u.phase];
  if (!rows) return '';
  const [icon, title, sub, actions] = rows;
  return `<div class="update" data-phase="${u.phase}" role="status">
    <span class="up-icon">${icon}</span>
    <div class="up-text"><strong>${title}</strong>${sub ? `<div class="up-sub">${sub}</div>` : ''}${notes && ['available', 'ready'].includes(u.phase) ? notes : ''}</div>
    ${actions ? `<div class="up-actions">${actions}</div>` : ''}
  </div>`;
}

function updateMenuItems() {
  const busy = !['idle', 'uptodate', 'error'].includes(state.update.phase);
  return `<div class="mi-header">Agent Gauge ${state.version}</div>
    <button role="menuitem" class="mi check-updates" ${busy ? 'disabled' : ''}><span class="tick"></span>Check for Updates…</button>
    <div class="mi-header">Automatic updates</div>
    ${Object.entries(MODES)
      .map(
        ([k, label]) =>
          `<button role="menuitemradio" class="mi set-mode" data-mode="${k}" aria-checked="${state.updateMode === k}"><span class="tick">${state.updateMode === k ? ICONS.check : ''}</span>${label}</button>`,
      )
      .join('')}
    <div class="sep"></div>`;
}

function setUpdate(patch) {
  const same = patch.phase === state.update.phase;
  Object.assign(state.update, patch);
  // Progress ticks update the bar in place, so buttons stay put and stay clickable.
  const bar = $('.update[data-phase=downloading] .up-bar span');
  if (same && patch.phase === 'downloading' && bar) {
    bar.style.width = `${state.update.progress}%`;
    $('.update .up-pct').textContent = `${state.update.progress}%`;
    return;
  }
  render();
}

async function checkFlow({ result = 'uptodate' } = {}) {
  setUpdate({ phase: 'checking', notes: false });
  await sleep(1300);
  if (result === 'error') return setUpdate({ phase: 'error' });
  if (result === 'found') return foundFlow();
  setUpdate({ phase: 'uptodate' });
  await sleep(4000);
  if (state.update.phase === 'uptodate') setUpdate({ phase: 'idle' });
}

// A new release was found: what happens next depends on the automatic-updates mode.
async function foundFlow() {
  if (state.updateMode !== 'download') return setUpdate({ phase: 'available' });
  await downloadFlow();
  setUpdate({ phase: 'ready' });
}

async function downloadFlow() {
  for (let p = 0; p <= 100; p += 7) {
    setUpdate({ phase: 'downloading', progress: Math.min(100, p) });
    await sleep(170);
  }
  setUpdate({ phase: 'extracting', progress: 100 });
  await sleep(900);
}

async function installFlow() {
  setUpdate({ phase: 'installing', notes: false });
  await sleep(1400);
  state.open = null;
  state.menu = false;
  state.version = NEXT;
  setUpdate({ phase: 'idle' });
  toast(`Agent Gauge would quit and open again, now at ${NEXT}.`);
}

function updateClick(t) {
  const hit = (sel) => t.closest(sel);
  if (hit('.check-updates')) {
    state.menu = false;
    checkFlow({ result: state.nextCheck });
    return true;
  }
  const mode = hit('.set-mode');
  if (mode) {
    state.updateMode = mode.dataset.mode;
    state.menu = false;
    render();
    return true;
  }
  if (hit('.toggle-notes')) return setUpdate({ notes: !state.update.notes }), true;
  if (hit('.later')) return setUpdate({ phase: 'idle', notes: false }), true;
  if (hit('.skip')) {
    setUpdate({ phase: 'idle', notes: false });
    toast(`Skipped ${NEXT}. You’ll hear about the next version.`);
    return true;
  }
  if (hit('.install')) {
    (async () => {
      await downloadFlow();
      await installFlow();
    })();
    return true;
  }
  if (hit('.cancel')) {
    epoch++; // stops the download flow
    setUpdate({ phase: state.updateMode === 'download' ? 'idle' : 'available' });
    toast('Download stopped. Nothing was installed.');
    return true;
  }
  if (hit('.restart')) return installFlow(), true;
  if (hit('.retry-update')) return checkFlow({ result: 'found' }), true;
  if (hit('.quit') && state.update.phase === 'ready') {
    state.open = null;
    state.version = NEXT;
    setUpdate({ phase: 'idle' });
    toast(`Agent Gauge would install ${NEXT} and quit. Next launch is ${NEXT}.`);
    return true;
  }
  return false;
}

const UPDATE_MOMENTS = UPDATES
  ? {
      upCheck: ['Check: up to date', moment(() => { state.open = 'claude'; checkFlow(); })],
      upQuiet: ['Found → downloads quietly', moment(() => { state.open = 'claude'; foundFlow(); })],
      upReady: ['Ready, restart', moment(() => { state.open = 'claude'; state.update.phase = 'ready'; })],
      upNotify: [
        'Found (tell-me mode)',
        moment(() => { state.open = 'claude'; state.updateMode = 'check'; state.update.phase = 'available'; }),
      ],
      upError: ['Check fails → retry', moment(() => { state.open = 'codex'; checkFlow({ result: 'error' }); })],
    }
  : {};

const FABLE_MOMENTS = FABLE
  ? {
      fableLow: [
        'Fable runs out first',
        moment(() => {
          state.claude.usage.fable = { used: 88, resetIn: 594 };
          state.open = 'claude';
        }),
      ],
      noFable: [
        'No Fable cap',
        moment(() => {
          state.claude.usage.fable = null;
          state.open = 'claude';
        }),
      ],
    }
  : {};

mockup({
  initial,
  markup,
  render: renderProduct,
  moments: {
    fresh: ['Fresh reading', moment(() => (state.open = 'claude'))],
    low: [
      'Running low',
      moment(() => {
        state.claude.usage.five = { used: 81, resetIn: 134 };
        state.open = 'claude';
      }),
    ],
    critical: [
      'Critical',
      moment(() => {
        state.claude.usage.five = { used: 96, resetIn: 41 };
        state.claude.usage.weekly = { used: 92, resetIn: 594 };
        state.claude.usage.fable = { used: 94, resetIn: 594 };
        state.open = 'claude';
      }),
    ],
    nolimit: ['No 5-hour limit', moment(() => (state.open = 'codex'))],
    stale: [
      'Stale',
      moment(() => {
        state.claude.usage.ageSec = 3 * 3600 + 200;
        state.open = 'claude';
      }),
    ],
    rolled: [
      'Reset passed',
      moment(() => {
        state.claude.usage.ageSec = 6 * 3600;
        state.claude.usage.five = { used: 64, resetIn: -50 };
        state.open = 'claude';
      }),
    ],
    setup: [
      'Not connected',
      moment(() => {
        state.claude.usage = null;
        state.claude.setup = 'Waiting for the first capture. Open a Claude Code session and send a message.';
        state.open = 'claude';
      }),
    ],
    error: [
      'Codex error → refresh',
      moment(() => {
        state.codex.error = 'Codex took too long to return usage.';
        state.codex.usage.ageSec = 42 * 60;
        state.open = 'codex';
      }),
    ],
    ...FABLE_MOMENTS,
    ...UPDATE_MOMENTS,
  },
  click(e) {
    const t = e.target;
    const si = t.closest('.status-item');
    if (si) {
      state.open = state.open === si.dataset.agent ? null : si.dataset.agent;
      state.menu = false;
      return render();
    }
    if (UPDATES && updateClick(t)) return;
    if (t.closest('.gear')) {
      state.menu = !state.menu;
      return render();
    }
    const tv = t.closest('.toggle-visible');
    if (tv) {
      const k = tv.dataset.agent;
      state.visible[k] = !state.visible[k];
      state.menu = false;
      if (!state.visible[k] && state.open === k) state.open = null;
      return render();
    }
    if (t.closest('.launch')) {
      state.launchAtLogin = !state.launchAtLogin;
      state.menu = false;
      return render();
    }
    if (t.closest('.welcome')) {
      state.menu = false;
      render();
      return toast('The welcome window would open here.');
    }
    if (t.closest('.refresh')) return refreshFlow();
    if (t.closest('.quit')) {
      state.open = null;
      render();
      return toast('Agent Gauge would quit here.');
    }
    if (t.closest('.menu-anchor') || t.closest('#popover')) {
      if (state.menu && !t.closest('.menu')) {
        state.menu = false;
        render();
      }
      return;
    }
    if (t.closest('.desktop') && state.open) {
      state.open = null;
      state.menu = false;
      render();
    }
  },
});
