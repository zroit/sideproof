"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { shrink } from "@/lib/photos";
import { Art } from "@/components/art";
import { Nav } from "@/components/ui";

/** Name the product and give its claims; the agent turns them into a trial plan. A shop's
 *  trial link (?product=CODE) brings the claims with it. */
export default function NewTrial() {
  const [code, setCode] = useState("");
  const [shop, setShop] = useState<{ name: string; shop: string } | null>(null);
  const [product, setProduct] = useState("");
  const [listing, setListing] = useState("");
  const [label, setLabel] = useState<{ blob: Blob; url: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const c = new URLSearchParams(window.location.search).get("product");
    if (c) {
      setCode(c);
      api.product(c).then(setShop, (e) => setError(e.message));
    }
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const t = await api.create({ product, listing, code }, label?.blob);
      window.location.href = `/trial/?id=${t.id}`;
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  if (busy)
    return (
      <>
        <Nav back={{ href: "/", label: "Home" }} />
        <main className="page center">
          <div className="thinking"><Art step={3} /></div>
          <h2>The agent is reading the claims and planning your trial</h2>
          <p className="muted">It picks what YouCam Skin AI can measure and how long to test. This takes up to a minute.</p>
        </main>
      </>
    );

  return (
    <>
      <Nav back={{ href: "/", label: "Home" }} />
      <main className="page narrow">
        <form onSubmit={submit} className="form">
          {shop ? (
            <>
              <h1>{shop.name}</h1>
              <p className="lead">A trial from {shop.shop}. The agent reads the product&apos;s claims from the shop.</p>
            </>
          ) : (
            <>
              <h1>What are you testing?</h1>
              <p className="lead">Give the agent the claims, typed or as a photo of the label.</p>
              <label>Product name<input value={product} onChange={(e) => setProduct(e.target.value)} required={!code} placeholder="Matte Balance Gel" /></label>
              <label>What does it claim?<textarea value={listing} onChange={(e) => setListing(e.target.value)} rows={4} placeholder="Paste the claims from the box or the shop page" /></label>
              <label className="file">
                <input type="file" accept="image/*" capture="environment" onChange={async (e) => { const f = e.target.files?.[0]; if (f) setLabel(await shrink(f, 2048, 0.9)); }} />
                <span className="btn btn-ghost">{label ? "Change the label photo" : "Add a photo of the label"}</span>
              </label>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {label && <img src={label.url} alt="The label" className="label-preview" />}
            </>
          )}
          <p className="note">The agent picks what YouCam Skin AI can measure, plans how long to test, and flags ingredients that should not go on a face without a doctor.</p>
          <button className="btn" disabled={!!code && !shop}>Plan my trial</button>
          {error && <p className="note danger">{error}</p>}
        </form>
      </main>
    </>
  );
}
