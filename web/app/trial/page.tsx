"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { api, type Trial } from "@/lib/api";
import { blobOf, load, save, shrink, type Saved } from "@/lib/photos";
import { SplitPhoto } from "@/components/photo";
import { TrialView } from "@/components/TrialView";
import { Nav, PhotoTips } from "@/components/ui";

export default function TrialPage() {
  const [id, setId] = useState("");
  const [t, setT] = useState<Trial | null>(null);
  const [pics, setPics] = useState<Saved>({});
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [retake, setRetake] = useState<string[] | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const poll = useRef<ReturnType<typeof setTimeout> | null>(null);

  const refresh = useCallback(async (trialId: string) => {
    try {
      const next = await api.trial(trialId);
      setT(next);
      if (poll.current) clearTimeout(poll.current);
      if (next.decision?.state === "thinking") poll.current = setTimeout(() => refresh(trialId), 3000);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    const trialId = new URLSearchParams(window.location.search).get("id") ?? "";
    setId(trialId);
    if (trialId) {
      refresh(trialId);
      load(trialId).then(setPics);
    }
    return () => { if (poll.current) clearTimeout(poll.current); };
  }, [refresh]);

  async function run(label: string, action: () => Promise<Trial>) {
    setBusy(label);
    setError("");
    try {
      setT(await action());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy("");
    }
  }

  async function onPhoto(f: File) {
    if (!t) return;
    setBusy("YouCam Skin AI is measuring both halves");
    setError("");
    setRetake(null);
    try {
      const photo = await shrink(f);
      const r = await api.scan(t.id, photo.blob);
      if ("retake" in r) {
        setRetake(r.retake);
        return;
      }
      const first = !pics.baseline;
      setPics(await save(t.id, {
        latest: photo.url,
        overlays: r.media?.overlays,
        midline: r.media?.midline,
        span: r.media?.span,
        ...(first ? { baseline: photo.url, baselineOverlays: r.media?.overlays } : {}),
      }));
      setT(r);
      if (r.decision?.state === "thinking") poll.current = setTimeout(() => refresh(t.id), 3000);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy("");
      if (file.current) file.current.value = "";
    }
  }

  async function promise() {
    if (!t || !pics.baseline) return;
    setBusy("YouCam AI Skin Simulation is drawing what the claims promise");
    setError("");
    try {
      const r = await api.promise(t.id, await blobOf(pics.baseline));
      setPics(await save(t.id, { promise: r.image }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy("");
    }
  }

  const camera = (text: string) => (
    <label className="file">
      <input ref={file} type="file" accept="image/*" onChange={(e) => { const f = e.target.files?.[0]; if (f) onPhoto(f); }} />
      <span className="btn">{text}</span>
    </label>
  );

  let panel: React.ReactNode = null;
  if (t) {
    const d = t.decision;
    const canStart = t.status === "baseline" && d?.allowed?.includes("start");
    const baselines = t.scans.filter((s) => s.phase === "baseline").length;
    let body: React.ReactNode = null;
    if (busy) {
      body = (<><h2>{busy}</h2><div className="progress"><span /></div></>);
    } else if (t.status === "baseline" && !canStart) {
      body = (
        <>
          <h2>Baseline photo {baselines + 1} of 2</h2>
          <p className="muted">{baselines === 0 ? "Before any product. These two photos measure your face's own left-right difference." : "A few minutes after the first one, same place, same light."}</p>
          <PhotoTips />
          {camera("Take baseline photo")}
        </>
      );
    } else if (canStart) {
      body = (
        <>
          <h2>Put the product on the shaded half only</h2>
          {pics.baseline ? (
            <SplitPhoto src={pics.baseline} alt="Your baseline photo with the half for the product shaded" midline={pics.midline} span={pics.span} treated={t.treated_image_side} tint treatedSrc={pics.promise} />
          ) : null}
          <p>{d?.message}</p>
          {pics.baseline && !pics.promise && (
            <button className="btn btn-ghost" onClick={promise}>See what the claims promise on your face</button>
          )}
          {pics.promise && <p className="caption">The shaded half shows the claims&apos; promise, drawn by YouCam AI Skin Simulation. The trial will measure what really happens.</p>}
          <button className="btn" onClick={() => run("Starting the trial", () => api.start(t.id))}>It&apos;s on: start the trial</button>
        </>
      );
    } else if (t.status === "running" || t.status === "concluding") {
      body = (
        <>
          <h2 className="agent-title"><span className="agent-dot" />Your trial agent</h2>
          <p className="big">{d?.state === "thinking" ? "Looking at the new scan…" : d?.message ?? "Take your first scan when the plan says."}</p>
          {d?.next_scan_in_hours != null && <p className="chip">Next scan in {d.next_scan_in_hours} h</p>}
          <div className="ctas">
            {camera("Take a scan")}
            <button className="btn btn-ghost" disabled={!Object.values(t.stats.concerns).some((c) => c.state === "measured")} onClick={() => run("The agent is writing the verdict", () => api.finish(t.id))}>Finish</button>
          </div>
        </>
      );
    } else if (t.status === "stopped" && !t.verdict) {
      body = (
        <>
          <p className="note danger">Stopped: the treated half got worse. Wash the product off; see a dermatologist if it stays.</p>
          <button className="btn btn-ghost" onClick={() => run("The agent is writing the verdict", () => api.finish(t.id))}>See the verdict</button>
        </>
      );
    }
    panel = body && (
      <section className="panel step">
        {body}
        {retake && <p className="note danger">Take it again: {retake.join(" ")} This photo was not measured, so it cost nothing.</p>}
        {error && <p className="note danger">{error}</p>}
      </section>
    );
  }

  return (
    <>
      <Nav back={{ href: "/", label: "Home" }} />
      <main className="page">
        {!id && <p className="note danger">No trial here. Start one from the home page.</p>}
        {id && !t && !error && <p className="muted">Loading your trial…</p>}
        {!t && error && <p className="note danger">{error}</p>}
        {t && <TrialView trial={t} pics={pics} actions={panel} />}
      </main>
    </>
  );
}
