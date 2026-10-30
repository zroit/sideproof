import Link from "next/link";
import type { ConcernStats } from "@/lib/api";

const FACE = "M96 70C70 73 47 93 47 127C48 151 69 175 96 177C123 175 144 151 145 127C145 93 122 73 96 70Z";

/** The mark: a woman's face, hair in a bun, split down the middle. The pink half had the product,
 *  the white half is the control; the hair is filled on the left and outlined on the right. The
 *  same drawing as SideProofMark in the app and app/tool/make_icons.py. */
export function Mark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="12 12 168 168" aria-hidden="true" className="mark">
      <defs>
        <clipPath id="sp-mark-left"><rect width="96" height="192" /></clipPath>
      </defs>
      <g stroke="#2B1E25" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="96" cy="38" r="22" fill="#FFF8F1" />
        <circle cx="96" cy="38" r="22" fill="#2B1E25" clipPath="url(#sp-mark-left)" />
        <path d="M101 19C112 22 118 31 115 44" fill="none" strokeWidth="2.6" />
        <ellipse cx="96" cy="98" rx="59" ry="62" fill="#FFF8F1" />
        <ellipse cx="96" cy="98" rx="59" ry="62" fill="#2B1E25" clipPath="url(#sp-mark-left)" />
        <path d="M99 38C124 41 144 59 151 88M100 52C121 58 136 74 141 98" fill="none" strokeWidth="2.6" />
        <path d={FACE} fill="#FFFFFF" />
        <path d={FACE} fill="#F2A3BB" stroke="none" clipPath="url(#sp-mark-left)" />
        <path d={FACE} fill="none" />
        <path d="M96 70V177" />
        <path d="M60 100Q73 93 87 98M105 98Q119 93 132 100M64 113Q75 120 86 113M106 113Q117 120 128 113M90 141Q96 145 102 141M84 154Q96 162 108 154" fill="none" strokeWidth="3" />
        <path d="M68.4 115.2L66.5 119M72.8 116.4L72 120.5M77.2 116.4L78 120.5M81.6 115.2L83.5 119M110.4 115.2L108.5 119M114.8 116.4L114 120.5M119.2 116.4L120 120.5M123.6 115.2L125.5 119" fill="none" strokeWidth="2" />
      </g>
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
  return <span className={`pill pill-${v || "wait"}`}>{v === "better" && <Tick />}{VERDICT[v] ?? "Waiting for scans"}</span>;
}

export function ClaimPill({ result }: { result: string }) {
  const kind = result.startsWith("supported") ? "better" : result.startsWith("not supported") ? "worse" : "unclear";
  return <span className={`pill pill-${kind}`}>{kind === "better" && <Tick />}{result}</span>;
}

function Tick() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M5 12.5l4.5 4.5L19 7" />
    </svg>
  );
}

/** How far a concern moved, as a ring: the effect in multiples of the noise threshold. A full
 *  sweep is 4 times the threshold; a result inside the noise stays a short arc. */
export function VerdictRing({ effect, threshold, verdict, size = 112 }: { effect?: number; threshold?: number; verdict?: string; size?: number }) {
  const ratio = effect !== undefined && threshold ? Math.abs(effect) / threshold : 0;
  const share = Math.min(1, ratio / 4);
  const id = `ring-${verdict ?? "x"}`;
  const stops = verdict === "worse" ? ["#F2A08F", "#B23A2E"] : verdict === "better" ? ["#F48FB1", "#B467E0"] : ["#F7C98E", "#D9893A"];
  return (
    <svg width={size} height={size} viewBox="0 0 112 112" className="ring" role="img" aria-label={`The change is ${ratio.toFixed(1)} times the noise`}>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor={stops[0]} /><stop offset="1" stopColor={stops[1]} /></linearGradient>
      </defs>
      <circle cx="56" cy="56" r="48" fill="none" stroke="#F3E8E4" strokeWidth="12" />
      <circle cx="56" cy="56" r="48" fill="none" stroke={`url(#${id})`} strokeWidth="12" strokeLinecap="round" strokeDasharray="302" strokeDashoffset={302 * (1 - Math.max(0.04, share))} className="ring-arc" />
      <text x="56" y="58" textAnchor="middle" style={{ font: "400 32px var(--display)", fill: "var(--ink)" }}>{ratio.toFixed(1)}×</text>
      <text x="56" y="77" textAnchor="middle" style={{ font: "700 10px var(--body)", fill: "var(--muted)" }}>{ratio >= 1 ? "past the noise" : "of the noise"}</text>
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
  const gid = `line-${stats.concern}${compact ? "-c" : ""}`;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="chart" role="img" aria-label={`${stats.label}: treated half against control over ${maxH} hours`}>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="#F48FB1" /><stop offset=".5" stopColor="#E3507E" /><stop offset="1" stopColor="#B467E0" /></linearGradient>
      </defs>
      <rect x={left} y={y(t)} width={w} height={y(-t) - y(t)} rx="11" className="chart-band" />
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
      <polyline points={pts} className="chart-line" stroke={`url(#${gid})`} />
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
