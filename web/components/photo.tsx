"use client";

import { useEffect, useRef, useState } from "react";

type Line = [[number, number], [number, number]];
type Side = "img_left" | "img_right";

/** The treated half of a photo as a CSS polygon, split along the face's midline. */
export function halfClip(midline: Line | undefined, treated: Side) {
  const [[x0], [x1]] = midline ?? [[0.5, 0], [0.5, 1]];
  const a = (x0 * 100).toFixed(2), b = (x1 * 100).toFixed(2);
  return treated === "img_right" ? `polygon(${a}% 0, 100% 0, 100% 100%, ${b}% 100%)` : `polygon(0 0, ${a}% 0, ${b}% 100%, 0 100%)`;
}

/** A face photo split at its midline: YouCam's mask on top, the treated half tinted or showing
 *  another picture (the promise), and each half labelled with what YouCam measured. The halves
 *  are cut along the whole line; the dashed line itself runs hairline to chin (span). */
export function SplitPhoto({
  src,
  alt,
  overlay,
  midline,
  span,
  treated,
  tint = false,
  treatedSrc,
  labels,
}: {
  src: string;
  alt: string;
  overlay?: string;
  midline?: Line;
  span?: [number, number];
  treated: Side;
  tint?: boolean;
  treatedSrc?: string;
  labels?: { treated: string; control: string };
}) {
  const clip = halfClip(midline, treated);
  const [[x0], [x1]] = midline ?? [[0.5, 0], [0.5, 1]];
  const [y0, y1] = span ?? [0, 1];
  const at = (y: number) => (x0 + (x1 - x0) * y) * 100;
  return (
    <figure className="split">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt={alt} />
      {treatedSrc && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={treatedSrc} alt="" className="layer" style={{ clipPath: clip }} />
      )}
      {tint && <div className="layer tint" style={{ clipPath: clip }} />}
      {overlay && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={overlay} alt="" className="layer overlay" />
      )}
      <svg className="layer" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
        <line x1={at(y0)} y1={y0 * 100} x2={at(y1)} y2={y1 * 100} className="midline" />
      </svg>
      {labels && (
        <div className={`half-labels ${treated === "img_right" ? "" : "flip"}`}>
          <span className="lab-control">{labels.control}</span>
          <span className="lab-treated">{labels.treated}</span>
        </div>
      )}
    </figure>
  );
}

/** Two pictures of the same face; drag across to wipe from one to the other. When it first
 *  comes into view the divider sweeps once, so it is clear there is something to drag; a
 *  close-up shows the part of the face the claim is about. */
export function Compare({
  before,
  after,
  beforeLabel,
  afterLabel,
  alt,
  closeUp,
}: {
  before: string;
  after: string;
  beforeLabel: string;
  afterLabel: string;
  alt: string;
  closeUp?: { scale: number; origin: string; label: string };
}) {
  const [pos, setPos] = useState(50);
  const [zoom, setZoom] = useState(!!closeUp);
  const [touched, setTouched] = useState(false);
  const box = useRef<HTMLElement>(null);

  useEffect(() => {
    if (touched || !box.current || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let raf = 0, start = 0;
    const sweep = (now: number) => {
      start ||= now;
      const k = (now - start) / 2600;
      if (k >= 1) return setPos(50);
      setPos(50 + 38 * Math.sin(k * Math.PI * 2) * (1 - k * 0.3));
      raf = requestAnimationFrame(sweep);
    };
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting) {
        raf = requestAnimationFrame(sweep);
        io.disconnect();
      }
    }, { threshold: 0.6 });
    io.observe(box.current);
    return () => { io.disconnect(); cancelAnimationFrame(raf); };
  }, [touched]);

  const lens = zoom && closeUp ? { transform: `scale(${closeUp.scale})`, transformOrigin: closeUp.origin } : undefined;
  return (
    <div className="compare-wrap">
      <figure className="compare" ref={box}>
        <div className="lens" style={lens}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={before} alt={alt} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={after} alt="" className="layer" style={{ clipPath: `inset(0 0 0 ${pos}%)` }} />
        </div>
        <div className="handle" style={{ left: `${pos}%` }} aria-hidden="true"><span /></div>
        <span className="corner left">{beforeLabel}</span>
        <span className="corner right">{afterLabel}</span>
        <input
          type="range" min={0} max={100} step={0.5} value={pos}
          onChange={(e) => { setTouched(true); setPos(Number(e.target.value)); }}
          onPointerDown={() => setTouched(true)}
          aria-label={`Drag between ${beforeLabel} and ${afterLabel}`}
        />
      </figure>
      {closeUp && (
        <div className="toggle small-toggle" role="tablist">
          <button role="tab" aria-selected={zoom} onClick={() => setZoom(true)}>{closeUp.label}</button>
          <button role="tab" aria-selected={!zoom} onClick={() => setZoom(false)}>Whole face</button>
        </div>
      )}
    </div>
  );
}
