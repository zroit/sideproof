"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, media, statusWords, type Trial } from "@/lib/api";
import { demoPics } from "@/lib/demo";
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

type Sides = Record<string, Record<string, { img_left: number; img_right: number }>>;

export default function Home() {
  const [demo, setDemo] = useState<Trial | null>(null);
  const [mine, setMine] = useState<{ id: string; product: string; status: string }[]>([]);
  useEffect(() => {
    api.demo().then(setDemo, () => {});
    api.trials().then(setMine, () => {});
  }, []);

  const pics = demo ? demoPics(demo) : { latest: media("latest.jpg"), baseline: media("baseline.jpg"), promise: media("promise.jpg"), overlays: { oiliness: media("latest-oiliness.png") } };
  const sides = (demo?.media as { sides?: Sides } | undefined)?.sides?.latest?.oiliness;
  const treated = demo?.treated_image_side ?? "img_right";
  const oil = demo?.stats.concerns.oiliness;

  return (
    <>
      <Nav />
      <main>
        <section className="hero">
          <div className="hero-text">
            <h1>Did it work, or was it the weather?</h1>
            <p className="lead">
              Put a skincare product on one half of your face and leave the other half alone. YouCam Skin AI measures both
              halves, so whatever differs is the product.
            </p>
            <div className="ctas">
              <Link href="/new/" className="btn">Start a trial</Link>
              <Link href="/demo/" className="btn btn-ghost">See a finished trial</Link>
            </div>
            <p className="apis">
              Built on YouCam <b>AI Skin Analysis</b>, <b>AI Skin Simulation</b> and <b>AI Fitzpatrick Skin Type</b>.
            </p>
          </div>
          <div className="hero-photo">
            <SplitPhoto
              src={pics.latest!}
              alt="YouCam's sample face eight hours into a trial, with YouCam's oiliness map"
              overlay={pics.overlays?.oiliness}
              midline={pics.midline}
              treated={treated}
              labels={sides ? { treated: `Treated half ${sides[treated].toFixed(1)}% oily`, control: `Control half ${sides[treated === "img_right" ? "img_left" : "img_right"].toFixed(1)}% oily` } : undefined}
            />
            <p className="caption">YouCam&apos;s oiliness map, 8 hours after a matte gel went on one half. YouCam&apos;s sample face; the gel is a digital filter.</p>
          </div>
        </section>

        <section id="how" className="section">
          <h2>A fair test, on half your face</h2>
          <p className="lead narrow">Dermatologists test products with a split-face trial. SideProof gives anyone the same design with a phone.</p>
          <ol className="steps">
            {STEPS.map((s, i) => (
              <li key={s.title}>
                <Art step={(i + 1) as 1 | 2 | 3 | 4} />
                <h3>{s.title}</h3>
                <p>{s.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="section">
          <h2>The promise, then the proof</h2>
          <p className="lead narrow">
            Before you start, YouCam AI Skin Simulation shows what the claims promise on your own face. Then the trial measures what
            actually happened.
          </p>
          <div className="two panel">
            <div>
              <Compare before={pics.baseline!} after={pics.promise!} beforeLabel="Before" afterLabel="The promise" alt="The sample face and YouCam's simulation of less shine" />
              <p className="caption">&ldquo;Controls shine for up to 8 hours&rdquo;, simulated by YouCam. Drag to compare.</p>
            </div>
            <div className="proof">
              {oil ? (
                <>
                  <div className="row"><h3>Oiliness, treated half against control</h3><VerdictPill verdict={oil.verdict} /></div>
                  <EffectChart stats={oil} />
                  <p className="caption">Measured by YouCam AI Skin Analysis at 1, 4 and 8 hours. The effect stayed far past the noise band, so the claim came out supported.</p>
                </>
              ) : (
                <p className="muted">Loading the measured result…</p>
              )}
              <Link href="/demo/" className="btn btn-ghost">Open the whole trial</Link>
            </div>
          </div>
        </section>

        <section id="brands" className="section brands">
          <div>
            <h2>For shops and brands</h2>
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
              <div className="widget-head"><Mark size={22} /> Not sure it works on you?</div>
              <p>Test the sample on half your face first.</p>
              <div className="widget-btn">Test it on half your face</div>
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
