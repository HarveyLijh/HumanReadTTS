// ReaderShell.jsx — shared Mac-native markdown reader chrome.
// Each variation passes its own ResizableFigure component as a child slot.

const SHELL = {
  bg: '#ffffff',
  sidebar: '#ececec',
  sidebarBorder: '#d8d6d2',
  text: '#1d1d1f',
  textMuted: '#6e6e73',
  accent: '#0a84ff',
  font: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif',
};

// One-time CSS for the shell (prefixed mr-)
if (typeof document !== 'undefined' && !document.getElementById('mr-styles')) {
  const s = document.createElement('style');
  s.id = 'mr-styles';
  s.textContent = `
    .mr-root{font-family:${SHELL.font};color:${SHELL.text};background:${SHELL.bg};display:flex;flex-direction:column;height:100%;width:100%;overflow:hidden;border-radius:10px;box-shadow:0 24px 64px rgba(0,0,0,0.18),0 0 0 0.5px rgba(0,0,0,0.18)}
    .mr-titlebar{display:flex;align-items:center;height:36px;padding:0 12px;background:linear-gradient(180deg,#f6f6f6,#ececec);border-bottom:0.5px solid #d8d6d2;flex-shrink:0;gap:10px}
    .mr-traffic{display:flex;gap:8px}
    .mr-traffic span{width:12px;height:12px;border-radius:50%;display:block}
    .mr-traffic .r{background:#ff5f57}.mr-traffic .y{background:#febc2e}.mr-traffic .g{background:#28c840}
    .mr-titlecenter{flex:1;text-align:center;font-size:12px;color:${SHELL.textMuted};font-weight:500}
    .mr-body{display:flex;flex:1;min-height:0}
    .mr-sidebar{width:200px;background:${SHELL.sidebar};border-right:0.5px solid ${SHELL.sidebarBorder};display:flex;flex-direction:column;flex-shrink:0;padding:10px 8px;gap:8px}
    .mr-sidebar-tabs{display:flex;gap:6px}
    .mr-stab{font-size:11px;padding:4px 8px;border-radius:5px;color:${SHELL.text};background:#d4eaff;font-weight:500;letter-spacing:-0.1px}
    .mr-stab.s{background:transparent;color:${SHELL.textMuted}}
    .mr-fileitem{padding:8px 10px;border-radius:6px;font-size:11.5px;color:${SHELL.text};line-height:1.35;cursor:default}
    .mr-fileitem.active{background:#fff;box-shadow:0 0 0 0.5px rgba(0,0,0,0.08),0 1px 2px rgba(0,0,0,0.04)}
    .mr-fileitem .t{font-size:10.5px;color:${SHELL.textMuted};margin-top:2px}
    .mr-main{flex:1;display:flex;flex-direction:column;min-width:0;background:${SHELL.bg}}
    .mr-tabbar{display:flex;align-items:center;height:36px;padding:0 14px;border-bottom:0.5px solid #e6e6e6;gap:14px;flex-shrink:0}
    .mr-tab{font-size:12px;padding:3px 10px;border-radius:5px;cursor:pointer;color:${SHELL.textMuted}}
    .mr-tab.active{background:${SHELL.accent};color:#fff;font-weight:500}
    .mr-doc{flex:1;overflow:auto;padding:32px 56px 80px;font-size:13px;line-height:1.7;color:#2c2c2e;letter-spacing:-0.01em}
    .mr-doc p{margin:0 0 14px}
    .mr-doc .lead strong{font-weight:600;color:#1d1d1f}
    .mr-doc em{font-style:italic}
    .mr-doc .caption{font-style:italic;font-size:12.5px;color:#3c3c3e;line-height:1.6;margin:14px 0 22px}
    .mr-doc .figure-wrap{margin:24px 0;display:flex;justify-content:center}
    .mr-playerbar{position:absolute;left:50%;bottom:18px;transform:translateX(-50%);background:rgba(245,245,247,0.92);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:0.5px solid rgba(0,0,0,0.08);border-radius:999px;padding:6px 14px;display:flex;align-items:center;gap:14px;font-size:11px;color:${SHELL.textMuted};box-shadow:0 8px 24px rgba(0,0,0,0.08);pointer-events:none}
    .mr-playerbar .pp{width:26px;height:26px;border-radius:50%;background:#0a84ff;color:#fff;display:flex;align-items:center;justify-content:center;font-size:11px}
    .mr-doc::-webkit-scrollbar{width:8px}
    .mr-doc::-webkit-scrollbar-thumb{background:rgba(0,0,0,0.18);border-radius:4px}
    .mr-doc::-webkit-scrollbar-track{background:transparent}
  `;
  document.head.appendChild(s);
}

function TitleBar() {
  return (
    <div className="mr-titlebar">
      <div className="mr-traffic"><span className="r"></span><span className="y"></span><span className="g"></span></div>
      <div className="mr-titlecenter">2026-04-28_Chapter3_ForMegy_v12.md</div>
      <div style={{ width: 60 }}></div>
    </div>
  );
}

function Sidebar() {
  return (
    <div className="mr-sidebar">
      <div className="mr-sidebar-tabs">
        <span className="mr-stab">Now</span>
        <span className="mr-stab s">Open…</span>
      </div>
      <div className="mr-fileitem active">
        <div>2026-04-28_Ch…ForMegy_v12.md</div>
        <div className="t">Today 23:38</div>
      </div>
      <div className="mr-fileitem">
        <div>thesis-outline.md</div>
        <div className="t">Yesterday</div>
      </div>
      <div className="mr-fileitem">
        <div>RQ1-pilot-notes.md</div>
        <div className="t">Apr 26</div>
      </div>
    </div>
  );
}

function TabBar() {
  return (
    <div className="mr-tabbar">
      <div className="mr-tab active">Preview</div>
      <div className="mr-tab">Source</div>
      <div style={{ flex: 1 }}></div>
      <div style={{ fontSize: 12, color: SHELL.textMuted }}>⌘F</div>
    </div>
  );
}

// A re-usable diagram placeholder rendered as an SVG so it scales cleanly.
// Mimics the small node-graph from the reference.
function DiagramSVG({ width, height }) {
  return (
    <svg viewBox="0 0 400 260" width={width} height={height} preserveAspectRatio="xMidYMid meet" style={{ display: 'block', background: '#fff' }}>
      <defs>
        <style>{`.nb{fill:#fff;stroke:#9aa0a6;stroke-width:1}.nl{font:6.5px -apple-system,sans-serif;fill:#3c4043}.ed{stroke:#9aa0a6;stroke-width:0.8;fill:none}.ed.d{stroke-dasharray:2 2}`}</style>
      </defs>
      {/* edges */}
      <path className="ed" d="M80,30 L80,60" /><path className="ed" d="M200,30 L200,60" /><path className="ed" d="M320,30 L320,60" />
      <path className="ed" d="M80,90 L60,130" /><path className="ed" d="M80,90 L100,130" />
      <path className="ed" d="M200,90 L160,130" /><path className="ed" d="M200,90 L200,130" /><path className="ed" d="M200,90 L240,130" />
      <path className="ed" d="M320,90 L300,130" /><path className="ed" d="M320,90 L340,130" />
      <path className="ed d" d="M100,160 L160,160" /><path className="ed d" d="M240,160 L300,160" />
      <path className="ed" d="M60,160 L60,200" /><path className="ed" d="M200,160 L200,200" /><path className="ed" d="M340,160 L340,200" />
      {/* nodes top row (yellow) */}
      <rect className="nb" x="55" y="10" width="50" height="22" rx="3" fill="#fef3a8" stroke="#d4b800" />
      <rect className="nb" x="175" y="10" width="50" height="22" rx="3" fill="#fef3a8" stroke="#d4b800" />
      <rect className="nb" x="295" y="10" width="50" height="22" rx="3" fill="#fef3a8" stroke="#d4b800" />
      <text className="nl" x="80" y="24" textAnchor="middle">alphabet seq</text>
      <text className="nl" x="200" y="24" textAnchor="middle">goal labels</text>
      <text className="nl" x="320" y="24" textAnchor="middle">trajectory</text>
      {/* nodes mid row */}
      <rect className="nb" x="55" y="60" width="50" height="30" rx="3" />
      <rect className="nb" x="175" y="60" width="50" height="30" rx="3" />
      <rect className="nb" x="295" y="60" width="50" height="30" rx="3" />
      <text className="nl" x="80" y="74" textAnchor="middle">plan library</text>
      <text className="nl" x="80" y="83" textAnchor="middle">induction</text>
      <text className="nl" x="200" y="74" textAnchor="middle">PR-canonical</text>
      <text className="nl" x="200" y="83" textAnchor="middle">inference</text>
      <text className="nl" x="320" y="74" textAnchor="middle">mode mapping</text>
      <text className="nl" x="320" y="83" textAnchor="middle">rules</text>
      {/* nodes lower */}
      <rect className="nb" x="35" y="130" width="50" height="30" rx="3" />
      <rect className="nb" x="85" y="130" width="40" height="30" rx="3" fill="#e8f0fe" stroke="#7a9be0" />
      <rect className="nb" x="135" y="130" width="50" height="30" rx="3" fill="#e8f0fe" stroke="#7a9be0" />
      <rect className="nb" x="185" y="130" width="50" height="30" rx="3" />
      <rect className="nb" x="225" y="130" width="50" height="30" rx="3" fill="#e8f0fe" stroke="#7a9be0" />
      <rect className="nb" x="275" y="130" width="50" height="30" rx="3" />
      <rect className="nb" x="325" y="130" width="40" height="30" rx="3" fill="#e8f0fe" stroke="#7a9be0" />
      {/* episodes */}
      <rect className="nb" x="40" y="200" width="40" height="20" rx="3" fill="#e6f4ea" stroke="#5a9c6f" />
      <rect className="nb" x="180" y="200" width="40" height="20" rx="3" fill="#e6f4ea" stroke="#5a9c6f" />
      <rect className="nb" x="320" y="200" width="40" height="20" rx="3" fill="#e6f4ea" stroke="#5a9c6f" />
      <text className="nl" x="60" y="213" textAnchor="middle">episode 1</text>
      <text className="nl" x="200" y="213" textAnchor="middle">episode 2</text>
      <text className="nl" x="340" y="213" textAnchor="middle">episode 3</text>
    </svg>
  );
}

// A photo-ish placeholder — striped diagonal bg + monospace label.
function PhotoSVG({ width, height, label }) {
  return (
    <svg viewBox="0 0 600 400" width={width} height={height} preserveAspectRatio="xMidYMid slice" style={{ display: 'block' }}>
      <defs>
        <pattern id="ph-stripes" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <rect width="14" height="14" fill="#eef0f3" />
          <line x1="0" y1="0" x2="0" y2="14" stroke="#dde1e7" strokeWidth="6" />
        </pattern>
      </defs>
      <rect width="600" height="400" fill="url(#ph-stripes)" />
      <text x="300" y="208" textAnchor="middle" fontFamily="ui-monospace, SFMono-Regular, Menlo, monospace" fontSize="16" fill="#7a8090" letterSpacing="1">
        {label || 'screenshot.png'}
      </text>
    </svg>
  );
}

// Top-of-doc text used by every variation. ResizableFigure is injected as a slot.
function DocBody({ ResizableFigure, baselineWidth = 320 }) {
  return (
    <div className="mr-doc">
      <p className="lead">
        <strong>Stage 2: Minimally-supervised plan library induction and plan-recognition inference.</strong> A behavioral
        alphabet is not a plan library; it is a vocabulary of behavioral primitives. Plans, in the plan-recognition
        sense, are hierarchical compositions of these primitives organized around player goals. Stage 2 induces a plan
        library from alphabet sequences and applies PR-canonical inference over the induced library.
        Figure 2 shows this stage with explicit separation of artifacts and processes.
      </p>

      <div className="figure-wrap">
        <ResizableFigure
          id="fig2"
          kind="diagram"
          baselineWidth={baselineWidth}
          aspect={400 / 260}
          render={(w, h) => <DiagramSVG width={w} height={h} />}
        />
      </div>

      <p className="caption">
        Figure 2. Stage 2 internal detail with explicit node-edge semantics. Nodes are data artifacts: alphabet sequences
        (input from Stage 1), goal labels (supervision input, yellow), the induced plan library (intermediate),
        the player trajectory under analysis (input to inference), the three PR-canonical signal time series
        (intermediate), and the four failure-to-adapt mode-labeled episode sets (output to Stage 3). Edges are labeled
        processes: sequential pattern mining produces the plan library; the three named PR-canonical operations
        consume the player trajectory and use the plan library as reference (dashed edges) to produce their respective
        signal time series; mode-mapping rules combine PR signals into mode-labeled episodes.
      </p>

      <p>
        Plan library induction proceeds by mining recurring sub-sequences in the alphabet from goal-labeled
        trajectories. The dissertation uses two sources of goal labels, neither of which requires expert annotation.
      </p>

      <p>
        <em>Telemetry-derivable goal labels (used in RQ-1).</em> On educational testbeds where game state is structured
        around explicit objectives, goal achievement is computable directly from the telemetry: level completion,
        sub-goal achievement, objective time-bounded performance, rubric-checkpoint passage. These signals are
        available without human labeling and provide ground-truth goal labels for plan library induction.
      </p>

      <div className="figure-wrap">
        <ResizableFigure
          id="fig3"
          kind="photo"
          baselineWidth={420}
          aspect={600 / 400}
          render={(w, h) => <PhotoSVG width={w} height={h} label="testbed-screenshot.png" />}
        />
      </div>

      <p className="caption">Figure 3. Educational testbed UI used in RQ-1, showing the rubric-checkpoint overlay.</p>

      <p>
        <em>LLM-weak goal labels (used in RQ-2).</em> On commercial-scale testbeds where telemetry-derivable goal labels
        are not available (because the games do not have the explicit objective structure educational games do), large
        language models are used as a weak supervision source. Given a window of telemetry plus game context, an LLM
        generates candidate goal descriptions that label what the player appeared to be attempting.
      </p>
    </div>
  );
}

function PlayerBar() {
  return (
    <div className="mr-playerbar">
      <span style={{ opacity: 0.6 }}>⏮</span>
      <span className="pp">▶</span>
      <span style={{ opacity: 0.6 }}>⏭</span>
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>0:00:00 / 0:43:16</span>
      <span style={{ opacity: 0.4 }}>⤤ 4</span>
      <span>1×</span>
      <span style={{ background: '#fff', borderRadius: 6, padding: '1px 6px', border: '0.5px solid rgba(0,0,0,0.1)' }}>Auto ▾</span>
    </div>
  );
}

function ReaderShell({ ResizableFigure, baselineWidth }) {
  return (
    <div className="mr-root" style={{ position: 'relative' }}>
      <TitleBar />
      <div className="mr-body">
        <Sidebar />
        <div className="mr-main">
          <TabBar />
          <DocBody ResizableFigure={ResizableFigure} baselineWidth={baselineWidth} />
        </div>
      </div>
      <PlayerBar />
    </div>
  );
}

Object.assign(window, { ReaderShell, DiagramSVG, PhotoSVG });
