"use client";

import { useEffect, useState } from "react";
import { api, type Trial } from "@/lib/api";
import { demoPics } from "@/lib/demo";
import { TrialView } from "@/components/TrialView";
import { Nav } from "@/components/ui";

export default function DemoPage() {
  const [trial, setTrial] = useState<Trial | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    api.demo().then(setTrial, (e) => setError(String(e.message ?? e)));
  }, []);
  return (
    <>
      <Nav back={{ href: "/", label: "Home" }} />
      <main className="page">
        {error && <p className="note danger">{error}</p>}
        {!trial && !error && <p className="muted">Loading the demo trial…</p>}
        {trial && <TrialView trial={trial} pics={demoPics(trial)} demo />}
      </main>
    </>
  );
}
