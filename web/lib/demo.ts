import { media, type Trial } from "./api";
import type { Saved } from "./photos";

/** The recorded demo trial's pictures, from its manifest, as the trial view expects them. */
export function demoPics(t: Trial): Saved {
  const m = (t.media ?? {}) as { photos?: Record<string, string>; overlays?: Record<string, Record<string, string>>; midline?: Saved["midline"]; span?: Saved["span"]; note?: string };
  const urls = (o?: Record<string, string>) => Object.fromEntries(Object.entries(o ?? {}).map(([k, v]) => [k, media(v)]));
  return {
    baseline: m.photos?.baseline && media(m.photos.baseline),
    latest: m.photos?.latest && media(m.photos.latest),
    promise: m.photos?.promise && media(m.photos.promise),
    overlays: urls(m.overlays?.latest),
    baselineOverlays: urls(m.overlays?.baseline),
    midline: m.midline,
    span: m.span,
    note: m.note,
  };
}

/** Where to look closely for a claim: the forehead for shine, a cheek on the treated half for
 *  redness, pores and spots. */
export function closeUpFor(concerns: string[], treated: "img_left" | "img_right") {
  if (concerns.includes("oiliness")) return { scale: 2.2, origin: "50% 22%", label: "Close-up: forehead" };
  return { scale: 2.3, origin: treated === "img_right" ? "68% 56%" : "32% 56%", label: "Close-up: cheek" };
}

/** How long a finished trial ran, in words. */
export function span(t: Trial): string {
  const hours = Math.max(0, ...Object.values(t.stats.concerns).flatMap((c) => (c.series ?? []).map((s) => s.hours)));
  return hours >= 48 ? `${Math.round(hours / 24)} days` : `${Math.round(hours)} hours`;
}
