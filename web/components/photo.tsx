"use client";

import { useState } from "react";

type Line = [[number, number], [number, number]];
type Side = "img_left" | "img_right";

/** The treated half of a photo as a CSS polygon, split along the face's midline. */
export function halfClip(midline: Line | undefined, treated: Side) {
  const [[x0], [x1]] = midline ?? [[0.5, 0], [0.5, 1]];
  const a = (x0 * 100).toFixed(2), b = (x1 * 100).toFixed(2);
  return treated === "img_right" ? `polygon(${a}% 0, 100% 0, 100% 100%, ${b}% 100%)` : `polygon(0 0, ${a}% 0, ${b}% 100%, 0 100%)`;
}

/** A face photo split at its midline: YouCam's mask on top, the treated half tinted or showing
 *  another picture (the promise), and each half labelled with what YouCam measured. */
export function SplitPhoto({
  src,
  alt,
  overlay,
  midline,
  treated,
  tint = false,
  treatedSrc,
  labels,
}: {
  src: string;
  alt: string;
  overlay?: string;
  midline?: Line;
  treated: Side;
  tint?: boolean;
  treatedSrc?: string;
  labels?: { treated: string; control: string };
}) {
  const clip = halfClip(midline, treated);
  const [[x0], [x1]] = midline ?? [[0.5, 0], [0.5, 1]];
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
        <line x1={x0 * 100} y1="0" x2={x1 * 100} y2="100" className="midline" />
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

/** Two pictures of the same face; drag across to wipe from one to the other. */
export function Compare({ before, after, beforeLabel, afterLabel, alt }: { before: string; after: string; beforeLabel: string; afterLabel: string; alt: string }) {
  const [pos, setPos] = useState(50);
  return (
    <figure className="compare">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={before} alt={alt} />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={after} alt="" className="layer" style={{ clipPath: `inset(0 0 0 ${pos}%)` }} />
      <div className="handle" style={{ left: `${pos}%` }} aria-hidden="true"><span /></div>
      <span className="corner left">{beforeLabel}</span>
      <span className="corner right">{afterLabel}</span>
      <input type="range" min={0} max={100} value={pos} onChange={(e) => setPos(Number(e.target.value))} aria-label={`Drag between ${beforeLabel} and ${afterLabel}`} />
    </figure>
  );
}
