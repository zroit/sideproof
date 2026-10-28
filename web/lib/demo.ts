import { media, type Trial } from "./api";
import type { Saved } from "./photos";

/** The recorded demo trial's pictures, from its manifest, as the trial view expects them. */
export function demoPics(t: Trial): Saved {
  const m = (t.media ?? {}) as { photos?: Record<string, string>; overlays?: Record<string, Record<string, string>>; midline?: Saved["midline"] };
  const urls = (o?: Record<string, string>) => Object.fromEntries(Object.entries(o ?? {}).map(([k, v]) => [k, media(v)]));
  return {
    baseline: m.photos?.baseline && media(m.photos.baseline),
    latest: m.photos?.latest && media(m.photos.latest),
    promise: m.photos?.promise && media(m.photos.promise),
    overlays: urls(m.overlays?.latest),
    baselineOverlays: urls(m.overlays?.baseline),
    midline: m.midline,
  };
}
