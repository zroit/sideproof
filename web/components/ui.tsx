import Link from "next/link";
import type { ConcernStats } from "@/lib/api";

/** The mark: a disc split down the middle; the filled half had the product. */
export function Mark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true" className="mark">
      <path d="M15 3A13 13 0 0 0 15 29Z" fill="var(--cobalt)" />
      <path d="M18.4 4.4A11.6 11.6 0 0 1 18.4 27.6Z" fill="none" stroke="currentColor" strokeWidth="2.8" strokeLinejoin="round" />
    </svg>
  );
}

export function Wordmark() {
  return (
    <Link href="/" className="wordmark" aria-label="SideProof home">
      <Mark size={26} />
      <span>SideProof</span>
    </Link>
  );
}

export function Nav({ back }: { back?: { href: string; label: string } }) {
  return (
    <header className="nav">
      <Wordmark />
      <nav>
        {back ? (
          <Link href={back.href}>{back.label}</Link>
        ) : (
          <>
            <Link href="/#how" className="hide-sm">How it works</Link>
            <Link href="/demo/" className="hide-sm">Demo</Link>
            <Link href="/#brands" className="hide-sm">For brands</Link>
            <Link href="/new/" className="btn btn-small">Start a trial</Link>
          </>
        )}
      </nav>
    </header>
  );
}

const VERDICT = { better: "Better", worse: "Worse", unclear: "Too early to tell" } as const;

export function VerdictPill({ verdict }: { verdict?: string | null }) {
  const v = (verdict ?? "") as keyof typeof VERDICT;
  return <span className={`pill pill-${v || "wait"}`}>{VERDICT[v] ?? "Waiting for scans"}</span>;
}

export function ClaimPill({ result }: { result: string }) {
  const kind = result.startsWith("supported") ? "better" : result.startsWith("not supported") ? "worse" : "unclear";
  return <span className={`pill pill-${kind}`}>{result}</span>;
}

/** The verdict as a picture: the control half grey, the treated half in the result's colour. */
export function VerdictDisc({ verdict, size = 64 }: { verdict?: string; size?: number }) {
  const colour = verdict === "better" ? "var(--better)" : verdict === "worse" ? "var(--worse)" : "var(--outline)";
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
      <path d="M15 2A14 14 0 0 0 15 30Z" fill="var(--mist)" />
      <path d="M17 2A14 14 0 0 1 17 30Z" fill={colour} />
    </svg>
  );
}

/** One concern over time: treated minus control, the face's own difference taken out. The band
 *  is the noise; below it the treated half has less of the concern. */
export function EffectChart({ stats, compact = false }: { stats: ConcernStats; compact?: boolean }) {
  const series = stats.series ?? [];
  if (!series.length) return null;
  const W = 520, H = compact ? 120 : 190, left = compact ? 6 : 52, bottom = compact ? 8 : 26;
  const w = W - left, h = H - bottom;
  const maxH = Math.max(1, ...series.map((s) => s.hours));
  const t = stats.threshold ?? 1;
  const span = Math.max(t * 1.6, ...series.map((s) => Math.abs(s.effect) * 1.15));
  const x = (hr: number) => left + 10 + (hr / maxH) * (w - 20);
  const y = (e: number) => h / 2 - (e / span) * (h / 2 - 8);
  const pts = series.map((s) => `${x(s.hours).toFixed(1)},${y(s.effect).toFixed(1)}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="chart" role="img" aria-label={`${stats.label}: treated half against control over ${maxH} hours`}>
      <rect x={left} y={y(t)} width={w} height={y(-t) - y(t)} rx="8" className="chart-band" />
      <line x1={left} x2={W} y1={y(0)} y2={y(0)} className="chart-zero" />
      {!compact && (
        <g className="chart-label">
          <text x="0" y="12">worse</text>
          <text x="0" y={h / 2 + 4}>noise</text>
          <text x="0" y={h - 2}>better</text>
          <text x={left + 4} y={H - 4}>0 h</text>
          <text x={W - 4} y={H - 4} textAnchor="end">{maxH.toFixed(0)} h</text>
        </g>
      )}
      <polyline points={pts} className="chart-line" />
      {series.map((s, i) => (
        <circle key={i} cx={x(s.hours)} cy={y(s.effect)} r={compact ? 5 : 6} className={s.phase === "baseline" ? "chart-dot-base" : "chart-dot"} />
      ))}
    </svg>
  );
}

const STEPS = ["Baseline", "Product on", "Scans", "Verdict"];

export function Timeline({ step, notes = [] }: { step: number; notes?: string[] }) {
  const finished = step >= STEPS.length - 1;
  return (
    <ol className="timeline" aria-label="Trial progress">
      {STEPS.map((name, i) => (
        <li key={name} className={i < step || finished ? "done" : i === step ? "now" : ""} aria-current={i === step ? "step" : undefined}>
          <span className="bar" />
          <b>{name}</b>
          {notes[i] && <small>{notes[i]}</small>}
        </li>
      ))}
    </ol>
  );
}

const TIPS = [
  ["M4 18h16M6 14a6 6 0 0 1 12 0M12 4v2M4.9 7.9l1.4 1.4M19.1 7.9l-1.4 1.4", "Face a window", "Even light on both halves"],
  ["M12 3a7 7 0 0 0-7 7v3a7 7 0 0 0 14 0v-3a7 7 0 0 0-7-7zM9 11h.01M15 11h.01M3 3l18 18", "Bare skin", "No makeup, hair back"],
  ["M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M9 12h6M12 9v6", "Look straight", "Phone at eye level"],
  ["M12 21s-6-5.3-6-11a6 6 0 0 1 12 0c0 5.7-6 11-6 11zM12 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z", "Same spot", "Same place every time"],
];

export function PhotoTips() {
  return (
    <ul className="tips">
      {TIPS.map(([d, title, sub]) => (
        <li key={title}>
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"><path d={d} /></svg>
          <span><b>{title}</b><small>{sub}</small></span>
        </li>
      ))}
    </ul>
  );
}
