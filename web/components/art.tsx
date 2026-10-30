/** The four "How it works" pictures, drawn in SVG and animated in CSS (they hold still when the
 *  system asks for less motion). One face, split at the midline, in different states. */

function Face({ split = true }: { split?: boolean }) {
  return (
    <g className="face">
      <path d="M38 152 Q42 128 74 126 L74 112 M126 112 L126 126 Q158 128 162 152" />
      <ellipse cx="100" cy="72" rx="44" ry="56" className={split ? "skin-control" : "skin"} />
      <g className="features">
        <path d="M74 66 Q82 61 90 66 M110 66 Q118 61 126 66" />
        <path d="M72 56 L90 54 M110 54 L128 56" />
        <path d="M101 74 L95 92 L104 93" />
        <path d="M88 106 Q100 112 112 106" />
      </g>
      {split && <line x1="100" y1="31" x2="100" y2="128" className="art-midline" />}
    </g>
  );
}

/** The hair, drawn over the halves, so the midline runs from the hairline to the chin. */
function Hair() {
  return <path d="M58 56 C50 22 74 9 100 9 C126 9 150 22 142 56 C136 40 120 31 100 31 C80 31 64 40 58 56 Z" className="hair" />;
}

const HALF = "M100 16 A44 56 0 0 1 100 128 Z";

export function Art({ step }: { step: 1 | 2 | 3 | 4 }) {
  if (step === 1)
    return (
      <svg viewBox="0 0 200 160" className="art art-weather" role="img" aria-label="Sun, cloud and night pass over the whole face">
        <Face split={false} />
        <ellipse cx="100" cy="72" rx="44" ry="56" className="wash" />
        <Hair />
        <g className="sky">
          <circle cx="168" cy="26" r="9" className="sun" />
          <path d="M152 34 a9 9 0 0 1 3-17 a12 12 0 0 1 22 4 a7 7 0 0 1 1 13 z" className="cloud" />
          <path d="M172 18 a11 11 0 1 0 6 18 a9 9 0 0 1 -6 -18 z" className="moon" />
        </g>
      </svg>
    );
  if (step === 2)
    return (
      <svg viewBox="0 0 200 160" className="art art-drop" role="img" aria-label="A drop of product lands on one half">
        <Face />
        <path d={HALF} className="treated grow" />
        <Hair />
        <path d="M124 8 q6 9 0 14 q-6 -5 0 -14z" className="drop" />
      </svg>
    );
  if (step === 3)
    return (
      <svg viewBox="0 0 200 160" className="art art-scan" role="img" aria-label="A scan line maps both halves">
        <defs>
          <clipPath id="head"><ellipse cx="100" cy="72" rx="44" ry="56" /></clipPath>
        </defs>
        <Face />
        <path d={HALF} className="treated" />
        <g clipPath="url(#head)">
          {[[72, 46], [84, 58], [66, 86], [80, 100], [90, 40], [118, 44], [128, 70], [112, 96], [134, 90], [106, 60]].map(([cx, cy], i) => (
            <circle key={i} cx={cx} cy={cy} r="2.6" className={`spot ${cx > 100 ? "spot-t" : ""}`} style={{ animationDelay: `${(cy / 128) * 1.6}s` }} />
          ))}
          <rect x="50" y="0" width="100" height="6" className="scanline" />
        </g>
        <Hair />
      </svg>
    );
  return (
    <svg viewBox="0 0 200 160" className="art art-chart" role="img" aria-label="The treated half's line leaves the noise band; the control half stays inside">
      <rect x="14" y="58" width="176" height="26" rx="6" className="band" />
      <text x="190" y="54" textAnchor="end" className="art-label">noise</text>
      <line x1="44" y1="30" x2="44" y2="138" className="divider" />
      <text x="14" y="152" className="art-label">baseline</text>
      <text x="190" y="152" textAnchor="end" className="art-label">after the product</text>
      <polyline points="14,71 34,67 54,75 74,66 94,73 114,65 134,72 154,67 174,70 190,68" className="line-control" />
      <polyline points="14,70 34,73 54,86 74,100 94,110 114,116 134,119 154,121 174,120 190,122" className="line-treated" />
    </svg>
  );
}
