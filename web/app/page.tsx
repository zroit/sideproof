"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, statusWords, type Trial } from "@/lib/api";
import type { Saved } from "@/lib/photos";
import { closeUpFor, demoPics, span } from "@/lib/demo";
import { Art } from "@/components/art";
import { Compare, SplitPhoto } from "@/components/photo";
import { EffectChart, Mark, Nav, VerdictPill } from "@/components/ui";

const SHOP_CODE = "A508A6"; // Kestrel & Fern's Matte Balance Gel, a made-up brand on the live dashboard

const STEPS = [
  { title: "Sleep, weather and light change your whole face", body: "So a before-and-after photo can't tell you what the product did." },
  { title: "The product goes on one half", body: "The app picks the half at random. The other half gets nothing: it is the control." },
  { title: "YouCam Skin AI maps both halves", body: "Each scan returns a map for every concern. SideProof splits it at your face's midline and measures each half." },
  { title: "Only a change past the noise counts", body: "Two photos before you start measure your face's own difference. The product has to beat it 2.5 times." },
] as const;


export default function Home() {
  const [demos, setDemos] = useState<Trial[]>([]);
  const [pick, setPick] = useState<number | null>(null);
  const [pickPromise, setPickPromise] = useState<number | null>(null);
  const [mine, setMine] = useState<{ id: string; product: string; status: string }[]>([]);
  useEffect(() => {
    api.demos().then((list) => Promise.all(list.map((d) => api.demo(d.id)))).then(setDemos, () => {});
    api.trials().then(setMine, () => {});
  }, []);
  // The hero opens on a trial whose claim came out supported (its map tells the story); the
  // promise section opens on another one, so both faces show at first glance.
  const heroDefault = Math.max(0, demos.findIndex((d) => Object.values(d.stats.concerns).some((c) => c.verdict === "better")));
  const heroIndex = pick ?? heroDefault;
  const promiseIndex = pickPromise ?? (demos.length > 1 ? (heroDefault + 1) % demos.length : 0);
  const demo = demos[heroIndex] ?? null;
  const pdemo = demos[promiseIndex] ?? null;
  const ppics: Saved = pdemo ? demoPics(pdemo) : {};
  const pclaimed = (pdemo?.plan.claims ?? []).map((c) => c.concern).filter(Boolean) as string[];
  const pshown = Object.values(pdemo?.stats.concerns ?? {}).find((c) => pclaimed.includes(c.concern) && c.series?.length);

  const pics: Saved = demo ? demoPics(demo) : {};
  const treated = demo?.treated_image_side ?? "img_right";
  const claimed = (demo?.plan.claims ?? []).map((c) => c.concern).filter(Boolean) as string[];
  // The concern to show: the first claimed one YouCam mapped; its numbers are the trial's own.
  const shown = Object.values(demo?.stats.concerns ?? {}).find((c) => claimed.includes(c.concern) && pics.overlays?.[c.concern]);
  const last = shown?.series?.[shown.series.length - 1];
  const oil = pshown;
  const switcher = (current: number, choose: (i: number) => void) =>
    demos.length > 1 && (
      <div className="demo-switch">
        {demos.map((d, i) => (
          <button key={d.id} aria-pressed={i === current} onClick={() => choose(i)}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={demoPics(d).latest} alt="" />
            <span>{d.product}<small>{span(d)}</small></span>
          </button>
        ))}
      </div>
    );

  return (
    <>
      <Nav />
      <main>
        <section className="hero">
          <div className="hero-text">
            <h1>Did it <em className="shimmer">work</em>, or was it the weather?</h1>
            <p className="lead">
              Put a skincare product on one half of your face and leave the other half alone. YouCam Skin AI measures both
              halves, so whatever differs is the product.
            </p>
            <div className="ctas">
              <Link href="/new/" className="btn">Start a trial</Link>
              <Link href="/demo/" className="btn btn-ghost">See a finished trial</Link>
            </div>
            <div className="apis" aria-label="Built on three YouCam APIs">
              <span className="chrome-chip">YouCam AI Skin Analysis</span>
              <span className="chrome-chip">AI Skin Simulation</span>
              <span className="chrome-chip">AI Fitzpatrick Skin Type</span>
            </div>
          </div>
          <div className="hero-photo">
            {switcher(heroIndex, setPick)}
            <div className="hero-card">
            {pics.latest ? <SplitPhoto
              key={demo?.id}
              src={pics.latest}
              alt={`One of YouCam's sample faces at the end of a trial, with YouCam's ${shown?.label.toLowerCase() ?? "oiliness"} map`}
              overlay={pics.overlays?.[shown?.concern ?? "oiliness"]}
              midline={pics.midline}
              treated={treated}
            /> : <div className="skeleton" />}
            {shown && last && (
              <div className="glass">
                <div className="row">
                  <span className="stat">{shown.verdict === "better" && last.control > 0 ? `${Math.round((1 - last.treated / last.control) * 100)}% less ${shown.label.toLowerCase()}` : shown.label}</span>
                  <VerdictPill verdict={shown.verdict} />
                </div>
                <div className="halves">
                  <span>Control {last.control.toFixed(1)}%</span>
                  <span className="t">Treated {last.treated.toFixed(1)}%</span>
                </div>
              </div>
            )}
            </div>
            <p className="caption">
              {shown ? `YouCam's ${shown.label.toLowerCase()} map ${demo ? span(demo) : ""} in: the share of each half YouCam marked. ` : ""}
              {pics.note ?? ""}
            </p>
          </div>
        </section>

        <section id="how" className="section">
          <h2>A fair test, on <em className="rose">half</em> your face</h2>
          <p className="lead narrow">Dermatologists test products with a split-face trial. SideProof gives anyone the same design with a phone.</p>
          <ol className="steps">
            {STEPS.map((s, i) => (
              <li key={s.title}>
                <Art step={(i + 1) as 1 | 2 | 3 | 4} />
                <h3><span className="num">{i + 1}</span>{s.title}</h3>
                <p>{s.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="section">
          <h2>The <em className="lilac">promise</em>, then the proof</h2>
          <p className="lead narrow">
            Before you start, YouCam AI Skin Simulation shows what the claims promise on your own face. Then the trial measures what
            actually happened.
          </p>
          {switcher(promiseIndex, setPickPromise)}
          <div className="two panel">
            <div>
              {ppics.baseline && ppics.promise ? <Compare key={pdemo?.id} before={ppics.baseline} after={ppics.promise} beforeLabel="Before" afterLabel="The promise" alt="The sample face and YouCam's simulation of the claims" closeUp={closeUpFor(pclaimed, pdemo?.treated_image_side ?? "img_right")} /> : <div className="skeleton" />}
              <p className="caption">The claims of {pdemo?.product ?? "the product"}, drawn on this face by YouCam AI Skin Simulation. Drag to compare.</p>
            </div>
            <div className="proof">
              {oil ? (
                <>
                  <div className="row"><h3>{oil.label}, treated half against control</h3><VerdictPill verdict={oil.verdict} /></div>
                  <EffectChart stats={oil} />
                  <p className="caption">Measured by YouCam AI Skin Analysis at every scan. Only a change past the noise band counts.</p>
                </>
              ) : (
                <p className="muted">Loading the measured result…</p>
              )}
              <Link href={pdemo ? `/demo/?id=${pdemo.id}` : "/demo/"} className="btn btn-ghost">Open the whole trial</Link>
            </div>
          </div>
        </section>

        <section id="brands" className="section brands">
          <div>
            <h2>For shops and <em className="rose">brands</em></h2>
            <p className="lead">A trial link sits next to Add to cart, or on the sample pack. Customers test before they buy; the brand learns what the product really does.</p>
            <ul className="ticks">
              <li>Outcomes per claim from real faces: better, too early, or worse</li>
              <li>Results by Fitzpatrick skin type, from YouCam</li>
              <li>A claim audit that won&apos;t call a claim backed without the trials</li>
            </ul>
            <div className="ctas">
              <a href={`/shop/${SHOP_CODE}`} className="btn">See it on a shop page</a>
              <a href="/dashboard" className="btn btn-ghost">Brand dashboard</a>
            </div>
          </div>
          <div className="widget" aria-hidden="true">
            <div className="widget-buy">Add to cart</div>
            <div className="widget-sp">
              <div>
                <div className="widget-head"><Mark size={30} /> Not sure it works <em className="rose">on you</em>?</div>
                <p>Test the sample on half your face first.</p>
                <div className="widget-btn">Test it on half your face</div>
              </div>
            </div>
          </div>
        </section>

        {mine.length > 0 && (
          <section className="section">
            <h2>Your trials</h2>
            <ul className="mine">
              {mine.map((t) => (
                <li key={t.id}>
                  <Link href={`/trial/?id=${t.id}`}>
                    <Mark size={24} />
                    <span><b>{t.product}</b><small>{statusWords(t.status)}</small></span>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        )}
      </main>
      <footer className="footer">
        <span>Photos are measured and dropped. Only the numbers are kept.</span>
        <span>SideProof, built for the YouCam API hackathon</span>
      </footer>
    </>
  );
}
