// The SideProof backend. The web build is served by the backend itself, so it talks to its own
// origin; NEXT_PUBLIC_API_BASE points a dev build elsewhere.
const BASE = process.env.NEXT_PUBLIC_API_BASE ?? "";

export type Series = { phase: string; hours: number; treated: number; control: number; effect: number };
export type ConcernStats = {
  concern: string;
  label: string;
  state: "need_baseline" | "ready" | "measured";
  baseline_scans: number;
  asymmetry?: number;
  noise?: number;
  threshold?: number;
  effect?: number;
  verdict?: "better" | "worse" | "unclear";
  series?: Series[];
};
export type Claim = { text: string; concern: string | null };
export type Plan = {
  product: string;
  claims: Claim[];
  concerns: string[];
  days: number;
  scan_every_hours: number;
  patch_first: boolean;
  safe_to_try: boolean;
  cautions: string[];
  summary: string;
};
export type Decision = { state: string; action?: string; message?: string; next_scan_in_hours?: number; allowed?: string[]; error?: string };
export type Verdict = { headline: string; concerns: { concern: string; verdict: string; text: string }[]; claims: { claim: string; result: string }[]; next: string };
export type Step = { job: string; thought?: string; tool?: string; final?: unknown; rejected?: string | null };
export type Media = {
  treated?: "img_left" | "img_right";
  midline?: [[number, number], [number, number]];
  overlays?: Record<string, string>;
  photos?: Record<string, string>;
};
export type Trial = {
  id: string;
  product: string;
  code: string | null;
  plan: Plan;
  status: "baseline" | "running" | "concluding" | "done" | "stopped";
  decision: Decision | null;
  verdict: Verdict | null;
  skin_type: string | null;
  treated_side: "left" | "right";
  treated_image_side: "img_left" | "img_right";
  hours_in: number;
  stats: { concerns: Record<string, ConcernStats>; harm: string[] };
  scans: { id: number; phase: string; at: number }[];
  agent_log: Step[];
  media?: Media & { overlays?: Record<string, Record<string, string>> | Record<string, string> };
};
export type ScanAnswer = Trial & { media?: { overlays: Record<string, string>; midline: [[number, number], [number, number]] } };
export type Retake = { retake: string[]; issues: string[] };

export function device(): string {
  let id = "";
  try {
    id = localStorage.getItem("sp_device") ?? "";
    if (!id) {
      const bytes = crypto.getRandomValues(new Uint8Array(18));
      id = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_");
      localStorage.setItem("sp_device", id);
    }
  } catch {
    id = "web-session-" + Math.random().toString(36).slice(2).padEnd(16, "0");
  }
  return id;
}

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("X-Device", device());
  const r = await fetch(BASE + path, { ...init, headers });
  const body = await r.json().catch(() => null);
  if (!r.ok) throw new Error(body && typeof body.detail === "string" ? body.detail : `Server error ${r.status}`);
  return body as T;
}

export const api = {
  trials: () => call<{ id: string; product: string; status: string; created_at: number }[]>("/api/trials"),
  trial: (id: string) => call<Trial>(`/api/trials/${id}`),
  demo: () => call<Trial>("/api/demo"),
  product: (code: string) => call<{ code: string; shop: string; name: string }>(`/api/products/${code}`),
  create: (fields: { product?: string; listing?: string; code?: string }, label?: Blob) => {
    const form = new FormData();
    form.set("product", fields.product ?? "");
    form.set("listing", fields.listing ?? "");
    form.set("code", fields.code ?? "");
    if (label) form.set("label", label, "label.jpg");
    return call<Trial>("/api/trials", { method: "POST", body: form });
  },
  scan: (id: string, photo: Blob) => {
    const form = new FormData();
    form.set("photo", photo, "scan.jpg");
    return call<ScanAnswer | Retake>(`/api/trials/${id}/scans`, { method: "POST", body: form });
  },
  promise: (id: string, photo: Blob) => {
    const form = new FormData();
    form.set("photo", photo, "baseline.jpg");
    return call<{ image: string; concerns: string[] }>(`/api/trials/${id}/promise`, { method: "POST", body: form });
  },
  start: (id: string) => call<Trial>(`/api/trials/${id}/start`, { method: "POST" }),
  finish: (id: string) => call<Trial>(`/api/trials/${id}/verdict`, { method: "POST" }),
};

export const media = (path: string) => `${BASE}/demo-media/${path}`;

export function statusWords(status: string): string {
  return (
    {
      baseline: "Taking the baseline photos",
      running: "In progress",
      concluding: "Ready for the verdict",
      done: "Finished",
      stopped: "Stopped: the treated half got worse",
    }[status] ?? status
  );
}
