"use client";

import { useEffect, useState } from "react";
import { api, media, type Trial } from "@/lib/api";
import { demoPics, span } from "@/lib/demo";
import { TrialView } from "@/components/TrialView";
import { Nav } from "@/components/ui";

export default function DemoPage() {
  const [demos, setDemos] = useState<{ id: string; product: string; cover: string | null }[]>([]);
  const [id, setId] = useState("");
  const [trial, setTrial] = useState<Trial | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const wanted = new URLSearchParams(window.location.search).get("id") ?? "";
    api.demos().then((list) => {
      setDemos(list);
      setId(wanted || list[0]?.id || "");
    }, (e) => setError(String(e.message ?? e)));
  }, []);

  useEffect(() => {
    if (!id) return;
    setTrial(null);
    api.demo(id).then(setTrial, (e) => setError(String(e.message ?? e)));
  }, [id]);

  return (
    <>
      <Nav back={{ href: "/", label: "Home" }} />
      <main className="page">
        {demos.length > 1 && (
          <div className="demo-switch trial">
            {demos.map((d) => (
              <button key={d.id} aria-pressed={d.id === id} onClick={() => { setId(d.id); history.replaceState(null, "", `?id=${d.id}`); }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                {d.cover && <img src={media(d.cover)} alt="" />}
                <span>{d.product}<small>{d.id === trial?.id ? span(trial) : "Finished trial"}</small></span>
              </button>
            ))}
          </div>
        )}
        {error && <p className="note danger">{error}</p>}
        {!trial && !error && <p className="muted">Loading the demo trial…</p>}
        {trial && <TrialView key={trial.id} trial={trial} pics={demoPics(trial)} demo />}
      </main>
    </>
  );
}
