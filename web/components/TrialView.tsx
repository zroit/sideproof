"use client";

import { useState, type ReactNode } from "react";
import type { ConcernStats, Trial } from "@/lib/api";
import { statusWords } from "@/lib/api";
import type { Saved } from "@/lib/photos";
import { closeUpFor } from "@/lib/demo";
import { Compare, SplitPhoto } from "./photo";
import { ClaimPill, EffectChart, Timeline, VerdictPill, VerdictRing } from "./ui";

export function stepOf(t: Trial): number {
  if (t.verdict) return 3;
  if (t.status === "baseline") return t.decision?.allowed?.includes("start") ? 1 : 0;
  return 2;
}

function overall(t: Trial): string {
  const v = Object.values(t.stats.concerns).map((c) => c.verdict);
  return v.includes("worse") ? "worse" : v.includes("better") ? "better" : "unclear";
}

const pct = (v?: number) => (v === undefined ? "" : `${v.toFixed(1)}%`);

/** Everything a trial shows: where it is, what YouCam saw on the photos, the promise against the
 *  proof, the verdict, a chart per concern, the plan and how the agent worked. */
export function TrialView({ trial: t, pics, actions, demo = false }: { trial: Trial; pics: Saved; actions?: ReactNode; demo?: boolean }) {
  const concerns = Object.values(t.stats.concerns);
  const measured = concerns.filter((c) => c.series?.length);
  const withMap = concerns.filter((c) => pics.overlays?.[c.concern]);
  const [shown, setShown] = useState<string | null>(withMap[0]?.concern ?? null);
  const current = withMap.find((c) => c.concern === shown) ?? withMap[0];
  const last = current?.series?.[current.series.length - 1];
  const claimed = t.plan.claims.map((c) => c.concern).filter(Boolean) as string[];
  const promiseConcern = concerns.find((c) => claimed.includes(c.concern) && c.series?.length);
  // The concern the verdict ring shows: a claimed one that was measured, the one that moved most.
  const lead = [...concerns].filter((c) => c.state === "measured").sort((a, b) => Math.abs(b.effect ?? 0) / (b.threshold ?? 1) - Math.abs(a.effect ?? 0) / (a.threshold ?? 1)).find((c) => claimed.includes(c.concern)) ?? concerns.find((c) => c.state === "measured");

  return (
    <div className="trial">
      <header className="trial-head">
        {demo && <p className="note">{pics.note ?? "A finished trial recorded through the real API on one of YouCam's sample faces."}</p>}
        <h1>{t.product}</h1>
        <div className="meta">
          <span className="chip">{statusWords(t.status)}</span>
          {t.skin_type && <span className="chip">Skin type {t.skin_type}</span>}
          <span className="chip chip-treated">Product on the {t.treated_side} side</span>
        </div>
        <Timeline step={stepOf(t)} notes={[t.status === "baseline" && stepOf(t) === 0 ? `${t.scans.length} of 2` : "", "", t.scans.filter((s) => s.phase === "trial").length ? `${t.scans.filter((s) => s.phase === "trial").length} done` : "", ""]} />
      </header>

      {actions}

      {t.verdict && (
        <div className="chrome">
        <section className="panel verdict">
          <div className="verdict-top">
            <VerdictRing effect={lead?.effect} threshold={lead?.threshold} verdict={lead?.verdict ?? overall(t)} />
            <div>
              <VerdictPill verdict={overall(t)} />
              <h2>{t.verdict.headline}</h2>
            </div>
          </div>
          {t.verdict.claims.length > 0 && (
            <ul className="claims">
              {t.verdict.claims.map((c) => (
                <li key={c.claim}><q>{c.claim}</q><ClaimPill result={c.result} /></li>
              ))}
            </ul>
          )}
          {t.verdict.next && <p className="muted">{t.verdict.next}</p>}
        </section>
        </div>
      )}

      {pics.latest && current && (
        <section className="panel">
          <h2>What <em className="rose">YouCam</em> saw</h2>
          <p className="muted">YouCam AI Skin Analysis returns a map for each concern. SideProof splits it at the midline of the face and measures each half.</p>
          {withMap.length > 1 && (
            <div className="toggle" role="tablist">
              {withMap.map((c) => (
                <button key={c.concern} role="tab" aria-selected={c.concern === current.concern} onClick={() => setShown(c.concern)}>{c.label}</button>
              ))}
            </div>
          )}
          <SplitPhoto
            src={pics.latest}
            alt={`The latest scan with YouCam's ${current.label.toLowerCase()} map`}
            overlay={pics.overlays?.[current.concern]}
            midline={pics.midline}
            span={pics.span}
            treated={t.treated_image_side}
            labels={last ? { treated: `Treated ${pct(last.treated)}`, control: `Control ${pct(last.control)}` } : undefined}
          />
          <p className="caption">{current.label}: share of each half YouCam marked{last ? `, ${last.hours.toFixed(0)} h in` : ""}.</p>
        </section>
      )}

      {pics.promise && pics.baseline && (
        <section className="panel promise">
          <h2>The <em className="lilac">promise</em> and the proof</h2>
          <div className="two">
            <div>
              <Compare before={pics.baseline} after={pics.promise} beforeLabel="Before" afterLabel="The promise" alt="The baseline photo and YouCam's simulation of the claims" closeUp={closeUpFor(claimed, t.treated_image_side)} />
              <p className="caption">The promise: YouCam AI Skin Simulation shows the claimed improvement on this face. Drag to compare.</p>
            </div>
            {promiseConcern && (
              <div className="proof">
                <div className="row"><h3>{promiseConcern.label}</h3><VerdictPill verdict={promiseConcern.verdict} /></div>
                <EffectChart stats={promiseConcern} />
                <p className="caption">The proof: the treated half against the control half, scan by scan, measured by YouCam AI Skin Analysis.</p>
              </div>
            )}
          </div>
        </section>
      )}

      {pics.baseline && pics.latest && !pics.promise && (
        <section className="panel">
          <h2>Before and now</h2>
          <Compare before={pics.baseline} after={pics.latest} beforeLabel="Baseline" afterLabel="Latest" alt="The baseline photo and the latest scan" />
        </section>
      )}

      {measured.length > 0 && (
        <section className="grid-2">
          {measured.map((c) => <ConcernCard key={c.concern} c={c} />)}
        </section>
      )}

      <section className="panel">
        <h2>The plan</h2>
        <p>{t.plan.summary}</p>
        <div className="meta">
          <span className="chip">{t.plan.days} {t.plan.days === 1 ? "day" : "days"}</span>
          <span className="chip">A scan every {t.plan.scan_every_hours} h</span>
          {t.plan.patch_first && <span className="chip">Small patch first</span>}
        </div>
        {!t.plan.safe_to_try && <p className="note danger">Do not try this without a doctor.</p>}
        {t.plan.cautions.map((c) => <p key={c} className="muted small">{c}</p>)}
      </section>

      {t.agent_log.length > 0 && (
        <details className="panel agent-log">
          <summary>
            <span>How the agent worked</span>
            <small>{t.agent_log.length} steps. Every number comes from YouCam or the trial math.</small>
          </summary>
          <ol>
            {t.agent_log.map((s, i) => (
              <li key={i}>
                <b>{{ plan: "Planning", next_step: "After a scan", verdict: "Verdict" }[s.job] ?? s.job}: </b>
                {s.tool ? `looked at ${s.tool}` : s.rejected ? "answer sent back" : "answered"}
                {s.thought && <p>{s.thought}</p>}
                {s.rejected && <p className="danger">Why: {s.rejected}</p>}
              </li>
            ))}
          </ol>
        </details>
      )}
    </div>
  );
}

function ConcernCard({ c }: { c: ConcernStats }) {
  return (
    <div className="panel concern">
      <div className="row"><h3>{c.label}</h3><VerdictPill verdict={c.state === "measured" ? c.verdict : null} /></div>
      <EffectChart stats={c} />
      <dl>
        <dt>Your face&apos;s own left-right difference</dt><dd>{c.asymmetry}</dd>
        <dt>Photo-to-photo noise</dt><dd>{c.noise} (a change counts past ±{c.threshold})</dd>
        {c.state === "measured" && (<><dt>Product effect</dt><dd><b>{c.effect}</b></dd></>)}
      </dl>
    </div>
  );
}
