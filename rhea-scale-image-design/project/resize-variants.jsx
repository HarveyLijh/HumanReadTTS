// resize-variants.jsx — Hover-slider ResizableFigure (final pick).
//
// Drop-in component for embedded markdown images/diagrams. On hover, a slim
// pill-shaped slider appears at the bottom of the figure. Drag or click the
// track to resize. Width is reported as a percentage of the doc column
// (COL_WIDTH below). Aspect ratio is preserved. Min/max clamped.
//
// Props:
//   id            — stable id for persistence (caller's responsibility)
//   baselineWidth — initial width in px
//   aspect        — width / height (preserved during resize)
//   render(w, h)  — render the figure body at the given dimensions
//
// Session-only state. To persist, lift `w` to the caller and write back
// to the markdown source (e.g. `{width=60%}`) on drag end.

const COL_WIDTH = 560; // doc column width — matches reader-shell padding

function clamp(n, min, max) { return Math.max(min, Math.min(max, n)); }

if (typeof document !== 'undefined' && !document.getElementById('rv-styles')) {
  const s = document.createElement('style');
  s.id = 'rv-styles';
  s.textContent = `
    .rv-fig{position:relative;display:inline-block;line-height:0;border-radius:4px}
    .rv-fig .rv-frame{position:relative;display:inline-block}
    .rv-fig .rv-frame > svg{display:block;border-radius:2px}

    /* Hover slider */
    .rv3 .rv-frame{position:relative}
    .rv3 .rv-slider{position:absolute;left:50%;bottom:8px;transform:translateX(-50%);display:flex;align-items:center;gap:8px;background:rgba(255,255,255,0.94);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:0.5px solid rgba(0,0,0,0.08);border-radius:999px;padding:5px 10px 5px 8px;opacity:0;transition:opacity .14s;box-shadow:0 4px 14px rgba(0,0,0,0.10);z-index:3}
    .rv3:hover .rv-slider, .rv3.dragging .rv-slider{opacity:1}
    .rv3 .rv-track{position:relative;width:120px;height:14px;display:flex;align-items:center;cursor:ew-resize}
    .rv3 .rv-track::before{content:'';position:absolute;left:0;right:0;top:50%;height:3px;border-radius:2px;background:rgba(0,0,0,0.10);transform:translateY(-50%)}
    .rv3 .rv-fill{position:absolute;left:0;top:50%;height:3px;border-radius:2px;background:#0a84ff;transform:translateY(-50%);pointer-events:none}
    .rv3 .rv-thumb{position:absolute;top:50%;width:14px;height:14px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.25),0 0 0 0.5px rgba(0,0,0,0.1);transform:translate(-50%,-50%);pointer-events:none}
    .rv3 .rv-icon{font-size:11px;color:#6e6e73;line-height:1;user-select:none}
    .rv3 .rv-pct{font:500 10.5px ui-monospace,SFMono-Regular,Menlo,monospace;color:#6e6e73;min-width:34px;text-align:right;font-variant-numeric:tabular-nums}
  `;
  document.head.appendChild(s);
}

function ResizableFigure_Slider({ id, baselineWidth, aspect, render }) {
  const min = 120, max = COL_WIDTH;
  const [w, setW] = React.useState(baselineWidth);
  const trackRef = React.useRef(null);
  const [dragging, setDragging] = React.useState(false);

  const setFromClientX = (clientX) => {
    const track = trackRef.current;
    if (!track) return;
    const rect = track.getBoundingClientRect();
    const t = clamp((clientX - rect.left) / rect.width, 0, 1);
    setW(min + t * (max - min));
  };

  const onTrackDown = (e) => {
    e.preventDefault();
    setDragging(true);
    setFromClientX(e.clientX);
    const move = (ev) => setFromClientX(ev.clientX);
    const up = () => {
      setDragging(false);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  const t = (w - min) / (max - min);
  const pct = Math.round((w / COL_WIDTH) * 100);
  const h = w / aspect;

  return (
    <div className={`rv-fig rv3 ${dragging ? 'dragging' : ''}`}>
      <div className="rv-frame" style={{ width: w, height: h }}>
        {render(w, h)}
        <div className="rv-slider">
          <span className="rv-icon">▣</span>
          <div className="rv-track" ref={trackRef} onPointerDown={onTrackDown}>
            <div className="rv-fill" style={{ width: `${t * 100}%` }}></div>
            <div className="rv-thumb" style={{ left: `${t * 100}%` }}></div>
          </div>
          <span className="rv-pct">{pct}%</span>
        </div>
      </div>
    </div>
  );
}

window.ResizableFigure_Slider = ResizableFigure_Slider;
