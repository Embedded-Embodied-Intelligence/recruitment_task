"""Build a self-contained HTML explorer of one dataset's benchmark runs.

    python -m edabench.explorer outputs/runs/v4_seed42 --out docs/explorer.html

The page needs no server and no install: the runs (scores, answers, responses) and the
curated findings (`findings.json` next to the runs) are embedded as JSON. `--fragment`
writes the page without the document skeleton, for hosts that add their own.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

QIDS = ["A1", "A2", "A3", "A4", "B1", "B2", "B3", "C1", "C2", "C3"]
QUESTION_LABELS = {
    "A1": "Unique batches", "A2": "Missing humidity", "A3": "Overall defect rate",
    "A4": "Median mold temp", "B1": "Direct drivers", "B2": "Leakage columns",
    "B3": "Regime change", "C1": "Best supplier", "C2": "Alpha humidity optimum",
    "C3": "Rate with regular cleaning",
}
MODEL_LABELS = {"claude-haiku": "Haiku 5.5", "claude-sonnet": "Sonnet 5.5", "claude-opus": "Opus 5.5"}


def collect(root: Path) -> dict:
    runs = []
    for score_path in sorted(root.glob("*/*/run_*/score.json")):
        run_dir = score_path.parent
        score = json.loads(score_path.read_text())
        meta = json.loads((run_dir / "metadata.json").read_text())
        response = run_dir / "response.md"
        runs.append({
            "id": run_dir.relative_to(root).as_posix(),
            "model": run_dir.parent.parent.name,
            "variant": run_dir.parent.name,
            "run": run_dir.name,
            "total": score["total"],
            "sections": score["sections"],
            "format_ok": score["format_ok"],
            "questions": score["questions"],
            "tool_calls": meta.get("n_tool_calls"),
            "duration_s": meta.get("duration_s"),
            "hit_turn_limit": meta.get("hit_turn_limit", False),
            "response": response.read_text() if response.exists() else "",
        })
    findings_path = root / "findings.json"
    findings = json.loads(findings_path.read_text()) if findings_path.exists() else {}
    # edabench.profile writes one profile for all datasets next to them.
    profile_path = root.parent / "profile.json"
    profile = json.loads(profile_path.read_text()) if profile_path.exists() else None
    return {"dataset": root.name, "runs": runs, "profile": profile, "qids": QIDS, "question_labels": QUESTION_LABELS,
            "model_labels": MODEL_LABELS, **findings}


def render(data: dict, fragment: bool = False) -> str:
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    page = TEMPLATE.replace("__DATA__", payload).replace("__TITLE__", data.get("title", "EDA-Bench results"))
    if fragment:
        return page
    return ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            "</head>\n<body>\n" + page + "\n</body>\n</html>\n")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", type=Path, help="outputs/runs/<dataset>")
    ap.add_argument("--out", type=Path, default=Path("docs/explorer.html"))
    ap.add_argument("--fragment", action="store_true", help="omit the document skeleton")
    args = ap.parse_args(argv)
    data = collect(args.root)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(data, args.fragment))
    print(f"wrote {args.out} ({len(data['runs'])} runs)")


TEMPLATE = r"""<title>__TITLE__</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500;600;700&family=Barlow:wght@400;500;600&family=JetBrains+Mono:wght@400;600&display=swap">
<style>
/* Layout: a plant QC report on one column, summary first, then the score grid, findings and the run browser. */
:root {
  --bg: #f4f6f7;
  --surface: #ffffff;
  --ink: #18242b;
  --ink-2: #4b5b64;
  --ink-3: #75848c;
  --rule: #d9e0e3;
  --accent: #0d6e74;
  --seq-lo: #e7f1f1;
  --seq-hi: #0b5a60;
  --on-strong: #ffffff;
  --warn: #a35a00;
  --warn-bg: #fbecd6;
  --bad: #b3261e;
  --bad-bg: #f8dedb;
  --ok: #2c6e3f;
  --font-display: "Barlow Semi Condensed", "Arial Narrow", "Helvetica Neue", Arial, sans-serif;
  --font-body: "Barlow", "Helvetica Neue", Arial, sans-serif;
  --font-data: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #0f1619; --surface: #162126; --ink: #e3eaec; --ink-2: #a9b7bd; --ink-3: #7f8f96;
    --rule: #2a3a41; --accent: #5cc3c8; --seq-lo: #1b2b30; --seq-hi: #4fb8be; --on-strong: #071214;
    --warn: #f0b35e; --warn-bg: #3a2a12; --bad: #f2928a; --bad-bg: #3d1d1a; --ok: #8fd19e;
    color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #0f1619; --surface: #162126; --ink: #e3eaec; --ink-2: #a9b7bd; --ink-3: #7f8f96;
  --rule: #2a3a41; --accent: #5cc3c8; --seq-lo: #1b2b30; --seq-hi: #4fb8be; --on-strong: #071214;
  --warn: #f0b35e; --warn-bg: #3a2a12; --bad: #f2928a; --bad-bg: #3d1d1a; --ok: #8fd19e;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 400 15px/1.55 var(--font-body);
}
.page {
  max-width: 1080px; margin: 0 auto;
  padding-block: 32px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: grid; gap: 40px;
}
h1, h2, h3 { font-family: var(--font-display); text-wrap: balance; margin: 0; letter-spacing: 0.01em; }
h1 { font-size: 2.2rem; font-weight: 700; line-height: 1.1; }
h2 { font-size: 1.35rem; font-weight: 600; }
h3 { font-size: 1.05rem; font-weight: 600; }
p { margin: 0; max-width: 68ch; }
.eyebrow { font: 600 0.75rem/1 var(--font-data); text-transform: uppercase; letter-spacing: 0.12em; color: var(--accent); }
.muted { color: var(--ink-2); }
.small { font-size: 0.85rem; }
section { display: grid; gap: 16px; min-width: 0; }
header { display: grid; gap: 12px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; }
.tile { background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 14px 16px; display: grid; gap: 2px; }
.tile .label { font: 600 0.72rem/1.2 var(--font-data); text-transform: uppercase; letter-spacing: 0.08em; color: var(--ink-3); }
.tile .value { font: 600 2rem/1.1 var(--font-display); font-variant-numeric: tabular-nums; }
.tile .sub { font-size: 0.85rem; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.controls { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.seg { display: inline-flex; border: 1px solid var(--rule); border-radius: 6px; overflow: hidden; background: var(--surface); }
.seg button {
  font: 500 0.85rem/1 var(--font-body); color: var(--ink-2); background: transparent; border: 0;
  padding: 8px 12px; cursor: pointer;
}
.seg button[aria-pressed="true"] { background: var(--accent); color: var(--on-strong); }
button:focus-visible, select:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.scroll { overflow-x: auto; background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
th, td { padding: 8px 10px; text-align: center; white-space: nowrap; }
thead th { font: 600 0.75rem/1.2 var(--font-data); color: var(--ink-2); border-bottom: 1px solid var(--rule); vertical-align: bottom; }
thead th .qlab { display: block; font: 400 0.7rem/1.2 var(--font-body); color: var(--ink-3); white-space: normal; min-width: 64px; }
tbody th { text-align: left; font-weight: 600; font-family: var(--font-body); }
tbody tr + tr > * { border-top: 1px solid var(--rule); }
td.cell { font: 500 0.85rem/1 var(--font-data); border-left: 2px solid var(--surface); }
td.total { font: 600 0.9rem/1 var(--font-data); }
.legend { display: flex; align-items: center; gap: 8px; font-size: 0.8rem; color: var(--ink-2); }
.legend .bar { width: 140px; height: 10px; border-radius: 2px; background: linear-gradient(90deg, var(--seq-lo), var(--seq-hi)); border: 1px solid var(--rule); }
.pill { display: inline-block; font: 600 0.72rem/1 var(--font-data); padding: 4px 6px; border-radius: 4px; }
.pill.warn { background: var(--warn-bg); color: var(--warn); }
.pill.none { color: var(--ink-3); }
.history { display: grid; gap: 6px; }
.hrow { display: grid; grid-template-columns: minmax(110px, 160px) 1fr 56px; gap: 10px; align-items: center; }
.hrow .who { font-size: 0.85rem; line-height: 1.25; min-width: 0; }
.hrow .who b { font-family: var(--font-display); font-weight: 600; display: block; }
.track { position: relative; height: 14px; background: var(--seq-lo); border-radius: 0 4px 4px 0; }
.track .fill { position: absolute; inset: 0 auto 0 0; background: var(--accent); border-radius: 0 4px 4px 0; }
.track .target { position: absolute; top: -4px; bottom: -4px; border-left: 1px dashed var(--ink-3); }
.hrow .num { font: 600 0.9rem/1 var(--font-data); text-align: right; }
.findings { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; }
.finding { background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 14px 16px; display: grid; gap: 8px; align-content: start; min-width: 0; }
.finding .meta { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.kind { font: 600 0.7rem/1 var(--font-data); text-transform: uppercase; letter-spacing: 0.08em; padding: 4px 6px; border-radius: 4px; background: var(--seq-lo); color: var(--accent); }
.kind.bad { background: var(--bad-bg); color: var(--bad); }
.kind.warn { background: var(--warn-bg); color: var(--warn); }
.runlinks { display: flex; flex-wrap: wrap; gap: 6px; }
.runlinks button { font: 500 0.75rem/1 var(--font-data); color: var(--accent); background: transparent; border: 1px solid var(--rule); border-radius: 4px; padding: 5px 7px; cursor: pointer; }
.browser { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr); gap: 16px; align-items: start; }
@media (max-width: 760px) { .browser { grid-template-columns: minmax(0, 1fr); } }
select { font: 500 0.9rem/1.2 var(--font-body); color: var(--ink); background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 8px 10px; max-width: 100%; }
.qtable td, .qtable th { text-align: left; white-space: normal; vertical-align: top; font-size: 0.85rem; }
.qtable td.code { font-family: var(--font-data); font-size: 0.78rem; word-break: break-word; }
.qtable td.sc { font-family: var(--font-data); text-align: right; white-space: nowrap; }
.response { background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 14px 16px; max-height: 560px; overflow: auto; white-space: pre-wrap; font: 400 0.82rem/1.5 var(--font-data); color: var(--ink); min-width: 0; }
.runhead { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: baseline; font-variant-numeric: tabular-nums; }
.runhead .big { font: 700 1.8rem/1 var(--font-display); }
.trapflag { color: var(--warn); font-weight: 600; }
footer { font-size: 0.82rem; color: var(--ink-3); border-top: 1px solid var(--rule); padding-top: 16px; }
code { font-family: var(--font-data); font-size: 0.85em; }
@media (prefers-reduced-motion: no-preference) { .track .fill { transition: width 0.4s ease; } }
</style>

<div class="page">
  <header>
    <div class="eyebrow" id="eyebrow">Benchmark report</div>
    <h1 id="title"></h1>
    <p class="muted" id="headline"></p>
  </header>

  <section aria-labelledby="h-summary">
    <h2 id="h-summary">Mean score per model</h2>
    <div class="tiles" id="tiles"></div>
    <p class="small muted">Full prompt. A score of 1 is the exact answer on all ten questions; 0 on a question is the naive answer its trap produces. <span id="hard-list"></span></p>
  </section>

  <section aria-labelledby="h-profile" id="profile-section" hidden>
    <h2 id="h-profile">Score by kind of skill</h2>
    <p class="small muted" id="profile-note"></p>
    <div class="scroll"><table id="profile"></table></div>
  </section>

  <section aria-labelledby="h-grid">
    <h2 id="h-grid">Score per question</h2>
    <div class="controls">
      <div class="seg" role="group" aria-label="Prompt variant" id="variant-seg"></div>
      <div class="legend"><span>0</span><span class="bar" aria-hidden="true"></span><span>1</span><span>mean over runs</span></div>
    </div>
    <div class="scroll"><table id="grid"></table></div>
  </section>

  <section aria-labelledby="h-traps">
    <h2 id="h-traps">How often the trap answer was given</h2>
    <p class="small muted">Share of runs whose answer was closer to the naive answer than to the truth (numbers), or matched the decoy (B3, C1).</p>
    <div class="scroll"><table id="traps"></table></div>
  </section>

  <section aria-labelledby="h-findings">
    <h2 id="h-findings">Where the points are lost</h2>
    <div class="findings" id="findings"></div>
  </section>

  <section aria-labelledby="h-history">
    <h2 id="h-history">Calibration history</h2>
    <p class="small muted">Mean total score at each stage. Each version moved the traps' clues further from plain sight. The dashed line marks the 0.7 upper end of the target band.</p>
    <div class="history" id="history"></div>
  </section>

  <section aria-labelledby="h-runs" id="runs">
    <h2 id="h-runs">Every run</h2>
    <div class="controls">
      <label class="small muted" for="run-select">Run</label>
      <select id="run-select"></select>
    </div>
    <div class="browser">
      <div style="display:grid; gap:12px; min-width:0">
        <div class="runhead" id="runhead"></div>
        <div class="scroll"><table class="qtable" id="qtable"></table></div>
      </div>
      <div class="response" id="response" tabindex="0" aria-label="Model response"></div>
    </div>
  </section>

  <footer id="footer"></footer>
</div>

<script>
const DATA = __DATA__;
const $ = (id) => document.getElementById(id);
const el = (tag, props = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") n.className = v; else if (k === "text") n.textContent = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v); else n.setAttribute(k, v);
  }
  for (const kid of kids) n.append(kid);
  return n;
};
const fmt = (x, d = 3) => (x == null || Number.isNaN(x) ? "–" : Number(x).toFixed(d));
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const sd = (xs) => { const m = mean(xs); return xs.length > 1 ? Math.sqrt(xs.reduce((a, b) => a + (b - m) ** 2, 0) / (xs.length - 1)) : 0; };
const label = (m) => DATA.model_labels[m] || m;
const MODEL_ORDER = ["claude-haiku", "claude-sonnet", "claude-opus"];
const models = [...new Set(DATA.runs.map((r) => r.model))].sort((a, b) => (MODEL_ORDER.indexOf(a) + 99 * (MODEL_ORDER.indexOf(a) < 0)) - (MODEL_ORDER.indexOf(b) + 99 * (MODEL_ORDER.indexOf(b) < 0)));
const variants = [...new Set(DATA.runs.map((r) => r.variant))];
const runsOf = (m, v) => DATA.runs.filter((r) => r.model === m && r.variant === v);
const qScore = (r, q) => (r.questions.find((x) => x.qid === q) || {}).score ?? 0;

$("title").textContent = DATA.title || "Benchmark results";
$("eyebrow").textContent = `Dataset ${DATA.dataset} · ${DATA.runs.length} scored runs`;
$("headline").textContent = DATA.headline || "";
$("hard-list").textContent = `Hard questions are ${(DATA.hard || ["A4", "B3", "C2", "C3"]).join(", ")}.`;

// Tiles. The weighted mean hides misses on the few hard questions, so each tile also gives the
// number of exactly right answers and the weighted score on the questions some model gets wrong.
const HARD = DATA.hard || ["A4", "B3", "C2", "C3"];
const exactCount = (r) => r.questions.filter((q) => q.score >= 0.999).length;
const hardScore = (r) => { const qs = r.questions.filter((q) => HARD.includes(q.qid)); const w = qs.reduce((a, q) => a + q.weight, 0); return w ? qs.reduce((a, q) => a + q.weight * q.score, 0) / w : 0; };
for (const m of models) {
  const rs = runsOf(m, "full"); if (!rs.length) continue;
  const t = rs.map((r) => r.total);
  $("tiles").append(el("div", { class: "tile" },
    el("span", { class: "label", text: label(m) }),
    el("span", { class: "value", text: fmt(mean(t)) }),
    el("span", { class: "sub", text: `${rs.length} runs · sd ${fmt(sd(t))} · ${fmt(Math.min(...t))}–${fmt(Math.max(...t))}` }),
    el("span", { class: "sub", text: `exact answers ${fmt(mean(rs.map(exactCount)), 1)}/10 · hard questions ${fmt(mean(rs.map(hardScore)))}` }),
    ...(rs.some((r) => !r.format_ok) ? [el("span", { class: "sub", text: `${rs.filter((r) => r.format_ok).length} runs with an answer: mean ${fmt(mean(rs.filter((r) => r.format_ok).map((r) => r.total)))}` })] : [])));
}

// Profile: the same answers grouped by what their trap demands (edabench.profile).
if (DATA.profile) {
  const P = DATA.profile;
  $("profile-section").hidden = false;
  $("profile-note").textContent = `Mean question score of the finished runs on ${P.datasets.join(" and ")}, ${P.variant} prompt.`;
  const head = el("tr", {}, el("th", { text: "Model" }));
  for (const lab of Object.values(P.categories)) head.append(el("th", { scope: "col" }, el("span", { class: "qlab", text: lab })));
  const body = el("tbody");
  for (const [m, row] of Object.entries(P.table)) {
    const tr = el("tr", {}, el("th", { scope: "row", text: `${label(m)} (${P.finished_runs[m]})` }));
    for (const c of Object.values(row)) {
      tr.append(c ? el("td", { class: "cell", style: cellStyle(c.mean), title: `${c.n} answers`, text: fmt(c.mean, 2) })
                  : el("td", { class: "small muted", text: "no runs" }));
    }
    body.append(tr);
  }
  $("profile").append(el("thead", {}, head), body);
}

// Score grid with a variant toggle
let variant = "full";
function cellStyle(v) {
  const p = Math.round(Math.max(0, Math.min(1, v)) * 100);
  return `background: color-mix(in oklab, var(--seq-hi) ${p}%, var(--seq-lo)); color: ${p > 55 ? "var(--on-strong)" : "var(--ink)"}`;
}
function drawGrid() {
  const t = $("grid"); t.replaceChildren();
  const head = el("tr", {}, el("th", { text: "Model" }));
  for (const q of DATA.qids) head.append(el("th", { scope: "col" }, q, el("span", { class: "qlab", text: DATA.question_labels[q] })));
  head.append(el("th", { scope: "col", text: "Total" }));
  t.append(el("thead", {}, head));
  const body = el("tbody");
  for (const m of models) {
    const rs = runsOf(m, variant); if (!rs.length) continue;
    const tr = el("tr", {}, el("th", { scope: "row", text: `${label(m)} (${rs.length})` }));
    for (const q of DATA.qids) {
      const xs = rs.map((r) => qScore(r, q)); const v = mean(xs);
      tr.append(el("td", { class: "cell", style: cellStyle(v), title: `${label(m)} · ${q}: mean ${fmt(v)}, sd ${fmt(sd(xs))}, ${rs.length} runs`, text: fmt(v, 2) }));
    }
    tr.append(el("td", { class: "total", text: fmt(mean(rs.map((r) => r.total))) }));
    body.append(tr);
  }
  t.append(body);
}
for (const v of variants) {
  const b = el("button", { type: "button", "aria-pressed": String(v === variant), text: v === "full" ? "Full prompt" : "Without the quality hint",
    onclick: () => { variant = v; for (const x of $("variant-seg").children) x.setAttribute("aria-pressed", String(x === b)); drawGrid(); } });
  $("variant-seg").append(b);
}
drawGrid();

// Trap hits (full prompt)
(function drawTraps() {
  const t = $("traps");
  const trapQs = DATA.qids.filter((q) => DATA.runs.some((r) => (r.questions.find((x) => x.qid === q) || {}).trap_hit !== undefined && (r.questions.find((x) => x.qid === q) || {}).trap_hit !== null));
  const head = el("tr", {}, el("th", { text: "Model" }));
  for (const q of trapQs) head.append(el("th", { scope: "col" }, q, el("span", { class: "qlab", text: DATA.question_labels[q] })));
  t.append(el("thead", {}, head));
  const body = el("tbody");
  for (const m of models) {
    const rs = runsOf(m, "full"); if (!rs.length) continue;
    const tr = el("tr", {}, el("th", { scope: "row", text: label(m) }));
    for (const q of trapQs) {
      const hits = rs.filter((r) => (r.questions.find((x) => x.qid === q) || {}).trap_hit === true).length;
      tr.append(el("td", {}, hits ? el("span", { class: "pill warn", text: `${hits}/${rs.length}` }) : el("span", { class: "pill none", text: `0/${rs.length}` })));
    }
    body.append(tr);
  }
  t.append(body);
})();

// Findings
const KIND = { estimation: ["Estimation", ""], reasoning: ["Reasoning", "bad"], missed: ["Missed", "bad"], ambiguity: ["Question wording", "warn"], decoy: ["Decoy", "bad"], format: ["Format", "warn"], found: ["Found", ""] };
for (const f of DATA.findings || []) {
  const [kname, kcls] = KIND[f.kind] || [f.kind, ""];
  const links = el("div", { class: "runlinks" });
  for (const id of f.runs || []) links.append(el("button", { type: "button", text: id, onclick: () => { showRun(id); $("runs").scrollIntoView({ behavior: "smooth", block: "start" }); } }));
  $("findings").append(el("article", { class: "finding" },
    el("div", { class: "meta" }, el("span", { class: `kind ${kcls}`, text: kname }), el("span", { class: "small muted", text: f.question })),
    el("h3", { text: f.title }), el("p", { class: "small", text: f.text }), links));
}

// History
for (const h of DATA.history || []) {
  const track = el("div", { class: "track", role: "img", "aria-label": `${h.stage}, ${h.setting}: ${fmt(h.score)}` },
    el("div", { class: "fill", style: `width:${(h.score * 100).toFixed(1)}%` }), el("div", { class: "target", style: "left:70%" }));
  $("history").append(el("div", { class: "hrow" },
    el("div", { class: "who" }, el("b", { text: h.stage }), el("span", { class: "muted", text: h.setting })),
    track, el("div", { class: "num", text: fmt(h.score) })));
}

// Run browser
const sel = $("run-select");
for (const r of DATA.runs) sel.append(el("option", { value: r.id, text: `${label(r.model)} · ${r.variant} · ${r.run} · ${fmt(r.total)}` }));
const show = (v) => (v == null ? "–" : typeof v === "object" ? (Array.isArray(v) ? v.join(", ") : Object.values(v).join(" ")) : String(v));
function showRun(id) {
  const r = DATA.runs.find((x) => x.id === id) || DATA.runs[0]; if (!r) return;
  sel.value = r.id;
  $("runhead").replaceChildren(
    el("span", { class: "big", text: fmt(r.total) }),
    el("span", { class: "small muted", text: `${label(r.model)} · ${r.variant} · ${r.run}` }),
    el("span", { class: "small muted", text: `${r.tool_calls ?? "–"} tool calls · ${r.duration_s ? Math.round(r.duration_s / 60) + " min" : "–"}${r.hit_turn_limit ? " · turn limit" : ""}${r.format_ok ? "" : " · answer format broken"}` }));
  const t = $("qtable"); t.replaceChildren();
  t.append(el("thead", {}, el("tr", {}, el("th", { text: "Q" }), el("th", { text: "Answer" }), el("th", { text: "Truth" }), el("th", { text: "Score" }))));
  const body = el("tbody");
  for (const q of r.questions) {
    body.append(el("tr", {},
      el("th", { scope: "row", title: DATA.question_labels[q.qid] || "", text: q.qid }),
      el("td", { class: "code", text: show(q.answer) }), el("td", { class: "code", text: show(q.truth) }),
      el("td", { class: "sc" }, fmt(q.score, 2), q.trap_hit ? el("span", { class: "trapflag", text: " trap" }) : "")));
  }
  t.append(body);
  $("response").textContent = r.response || "(no response text)";
}
sel.addEventListener("change", () => showRun(sel.value));
const median = [...runsOf("claude-sonnet", "full")].sort((a, b) => a.total - b.total);
showRun((median[Math.floor(median.length / 2)] || DATA.runs[0] || {}).id);

$("footer").textContent = "Generated by edabench.explorer from outputs/runs/" + DATA.dataset + ". Scores come from edabench.scorer against eval/ground_truth.json; the models never saw the key.";
</script>"""


if __name__ == "__main__":
    main()
