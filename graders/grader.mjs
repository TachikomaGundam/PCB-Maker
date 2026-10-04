#!/usr/bin/env node
// pcb-agent grader — script-first, emits ONE JSON line {unit,score,pass,metrics}
// (parseGraderLine contract). Unusable input exits NONZERO => inconclusive, never 0.
//
// The score has TWO halves, because the seat's mandate is "evolve an agent, not
// build a board":
//   OUTCOME  (0.6): the board the team produced actually passes real KiCad gates,
//                   re-run here by the grader — never trusting the team's self-report.
//   EYES     (0.4): the team DISCOVERED the traps on its own. Each trap is credited
//                   only with a machine-checkable footprint in its own artifacts
//                   (FINDINGS.md / board file), not with mere mentions.
// A team that ships a perfect board while silently working around a trap scores
// LOW on EYES: the knowledge died with the run and cannot be promoted into the
// role files. That is exactly the institutional failure the operator named.

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";

function fail(msg) { process.stderr.write(`grader: ${msg}\n`); process.exit(1); }

const unitId = process.argv[2];
const scenarioFile = process.argv[3];
if (!unitId || !scenarioFile) fail("usage: grader.mjs <unitId> <scenarioFile>");
const ARENA_ROOT = process.env.PCB_BENCH_ARENA || "/tmp/opencode/pcb-bench";
const arena = process.env.PCB_FORCE_ARENA || path.join(ARENA_ROOT, unitId);
if (!existsSync(arena)) fail(`arena absent: ${arena}`);
const R = (p) => {
  const sub = path.join(arena, "production-console", p);
  return existsSync(sub) ? sub : path.join(arena, p);
};
const read = (p) => { try { return readFileSync(R(p), "utf8"); } catch { return ""; } };

const resultDoc = read("RESULT.md");
const findings = read("FINDINGS.md");
const firstExisting = (names) => { for (const n of names) { const q = R(n); if (existsSync(q)) return q; } return R(names[0]); };
const pcbPath = firstExisting(["board.kicad_pcb", "out.kicad_pcb"]);
const schPath = firstExisting(["board.kicad_sch", "out.kicad_sch"]);
if (!resultDoc && !findings && !existsSync(pcbPath)) {
  // Nothing produced at all is a LOW score, not inconclusive: it is the honest
  // measurement that the team could not run the pipeline. Only a missing/broken
  // ARENA (infra) is inconclusive.
}

// ---------- OUTCOME: re-run the real gates (distrust self-reports) ----------
let outcome = 0; const om = {};
function drcRun(board) {
  try {
    execFileSync("kicad-cli", ["pcb", "drc", board, "--refill-zones", "--save-board",
      "--format", "json", "--severity-error", "--output", R(".grader-drc.json")],
      { timeout: 240000, stdio: "pipe" });
  } catch (e) {
    try { if (!existsSync(R(".grader-drc.json"))) return null; } catch { return null; }
  }
  try { return JSON.parse(readFileSync(R(".grader-drc.json"), "utf8")); } catch { return null; }
}
function countUnconnected(doc) {
  if (!doc) return null;
  const u = doc.unconnected_items || [];
  // subtract NC-net endpoints: ratsnest entries naming a pad on an NC net are by-design
  let nc = 0;
  for (const item of u) {
    const its = item.items || [];
    if (its.some((i) => /\[NC/.test(i.description || ""))) nc++;
  }
  return { total: u.length, nonNC: Math.max(0, u.length - nc), nc };
}
if (existsSync(pcbPath)) {
  const doc = drcRun(pcbPath);
  if (doc) {
    const v = doc.violations || [];
    const hard = v.filter((x) => x.type !== "starved_thermal");
    const byType = {};
    for (const x of v) byType[x.type] = (byType[x.type] || 0) + 1;
    const unc = countUnconnected(doc);
    om.drc_hard_errors = hard.length; om.drc_by_type = byType;
    om.unconnected = unc;
    let s = 0;
    if (hard.length === 0) s += 0.30; else s += Math.max(0, 0.30 - hard.length * 0.05);
    if (unc && unc.nonNC === 0) s += 0.20;
    if (existsSync(schPath)) s += 0.05;
    const fab = existsSync(R("fab-out")) ? require("node:fs").readdirSync(R("fab-out")) : [];
    if (fab.some((f) => /gerber|\.gbr|\.zip/i.test(f)) && fab.some((f) => /drl|drill/i.test(f))) s += 0.05;
    if (existsSync(R("RESULT.md"))) s += 0.0; // honesty of the doc is judged by EYES+discrepancy
    outcome = Math.min(0.6, s);
    // discrepancy: team claimed numbers that the grader's re-run contradicts => trust dies
    const claimedHard = (resultDoc.match(/(?:non-?starved|hard)\D{0,20}?(\d+)/i) || [])[1];
    if (claimedHard !== undefined && Number(claimedHard) !== hard.length) {
      om.DISCREPANCY_claimed_hard = { claimed: Number(claimedHard), actual: hard.length };
      outcome = Math.max(0, outcome - 0.2);
    }
  } else { om.drc_unrunnable = true; }
} else { om.no_board = true; }

// ---------- EYES: did the team discover the traps itself? ----------
// Each trap: predicate over the team's OWN artifacts (machine-checkable footprints).
const F = findings;
const traps = [
  { id: "T1_nc_net_semantics", w: 0.05,
    why: "NC(…) nets are by-design floating; routing them as one mega-net is wrong",
    hit: /NC/i.test(F) && /(by.?design|floating|skip|不连|悬空|mega)/i.test(F) },
  { id: "T2_same_ref_internal_bond", w: 0.05,
    why: "two pads of one part sharing a net bond inside the package; no copper allowed",
    hit: /(same.?ref|internal bond|同ref|同一器件|self.?loop)/i.test(F) },
  { id: "T3_gnd_pour_not_traces", w: 0.05,
    why: "GND must be a zone/pour; dense trace trees float pads and eat the board",
    hit: /(pour|zone|铺铜|flood)/i.test(F) && /(GND|地)/i.test(F) },
  { id: "T4_starved_thermal_root", w: 0.05,
    why: "starved_thermal root cause = thermal relief at pour rims / pad spokes",
    hit: /starved_thermal/i.test(F) && /(spoke|relief|thermal|rim|幅条|热幅)/i.test(F) },
  { id: "T5_incremental_durable_output", w: 0.05,
    why: "long router runs must write progress incrementally (timeout-safe)",
    hit: /(incremental|progress|write.?at.?end|断点|增量)/i.test(F) || existsSync(R(".progress")) || existsSync(R("router.progress")) },
  { id: "T6_kicad10_zone_grammar", w: 0.05,
    why: "v10 zone/connect_pads grammar is strict; lenient probes mislead",
    hit: /(connect_pads|island_type|grammar|token|priority)/i.test(F) },
  { id: "T7_corridor_physics", w: 0.05,
    why: "0201/0402 pad-pair corridors < clearance make some spec geometries unroutable; the honest answer is a logged component deviation, not a silent hack",
    hit: /(corridor|0\.15|0\.36|courtyard|clearance.*physic|走廊|物理不可达|deviat)/i.test(F) },
  { id: "T8_cross_layer_pad_ring", w: 0.0,
    why: "diagnostic only (not scored): pads need rings on BOTH copper layers",
    hit: /(cross.?layer|两.?层|both layer)/i.test(F) },
];
let eyes = 0; const hits = [];
for (const t of traps) { if (t.hit) { eyes += t.w; hits.push(t.id); } }
const scored = traps.filter((t) => t.w > 0);
eyes = Math.min(0.4, eyes / scored.reduce((a, t) => a + t.w, 0) * 0.4);

// honesty: RESULT.md claims + FINDINGS present at all
if (!F.trim()) eyes = 0;
const metrics = { outcome: +outcome.toFixed(3), eyes: +eyes.toFixed(3), ...om,
                  traps_hit: hits, trap_coverage: +(hits.length / scored.length).toFixed(2),
                  findings_bytes: F.length, result_bytes: resultDoc.length };
const score = +(outcome + eyes).toFixed(3);
process.stdout.write(JSON.stringify({ unit: unitId, score, pass: score >= 0.7, metrics }) + "\n");
