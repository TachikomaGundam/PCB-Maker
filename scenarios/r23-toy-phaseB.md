# r23-toy-phaseB — PCB family mission (phase B: route + copper, on a placed board)

You are the PCB orchestrator. Command your family through the control plane
(pcb_dispatch + capability receipts). Phase A inputs are ALREADY in the arena:
`spec.json`, `board.kicad_sch` (ERC-clean), `board.kicad_pcb` (DRC-clean placed,
ratsnest pending). Your phase B scope: make it manufacturable.

## Deliverables (incremental writes; budget discipline below)
1. `board-routed.kicad_pcb` — tracks+vias added to the placed board
   - gate: ratsnest `unconnected_items` reaches 0 for every non-NC net (NC nets
     are floating BY DESIGN — record in FINDINGS why they need no copper)
   - gate: zero crossing segments; power nets follow net-class widths (state which
     widths you chose and why in RESULT.md)
2. GND copper pour — dual-layer zones with stitching vias
   - gate: run DRC WITH native zone refill; report the refill posture you used
     and any zone-grammar traps you hit (F.Cu/B.Cu connect policy, thermal spokes,
     edge clearances) — name each trap class in FINDINGS.md
3. `RESULT.md` — exact gate commands + observed numbers, including the FIRST
   failing measurement before any fix (no victory-only history)

## Ground rules
- A fix that lives only in a docstring did not happen: FINDINGS.md entries land
  at discovery time, before designing the repair.
- If the geometry admits no legal 0.25mm route (fine-pitch gaps), that is a
  FAB-CAPABILITY finding: state the physical arithmetic, propose alternatives
  (narrow pair / layer escape), do not force illegal copper.
- Same-part pins sharing a net bond INTERNALLY — no copper between them; justify
  via FINDINGS.
- Wall budget ≈ 30 minutes. Partial + honest > ambitious + lost.
