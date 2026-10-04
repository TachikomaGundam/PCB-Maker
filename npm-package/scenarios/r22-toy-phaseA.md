# r22-toy-phaseA — PCB family mission (phase A: spec → schematic → placement)

You are the PCB orchestrator. Command your family through the control plane
(pcb_dispatch with capability receipts). This phase ENDS at placed-and-verified
board layout — routing and copper pour are LATER phases and out of scope.

## Inputs (already in the arena)
- `spec.json` — the component/netlist spec (authoritative)
- `BRIEF.txt` — the customer brief for this fixture board

## Deliverables (all must exist at repo/workspace root before you finish)
1. `board.kicad_sch` — schematic authored from spec.json
   - gate: `kicad-cli sch erc` reports 0 error-severity violations
   - gate: netlist roundtrip: every net's pin membership matches spec.json exactly
2. `board.kicad_pcb` — placement of real footprints for every component
   - gate: `kicad-cli pcb drc` reports 0 error-severity violations (unconnected ratsnest rows are EXPECTED at this phase — they are not errors)
3. `FINDINGS.md` — append-only defect ledger: every surprise, contradiction between
   spec/footprint/reality, and every decision with its evidence, written AT DISCOVERY TIME
4. `RESULT.md` — exact commands you used to measure each gate + the numbers you saw

## Budget discipline
Wall budget ≈ 25 minutes. Commit deliverables incrementally (write partial,
improve in place). A finished phase A with honest FINDINGS beats an ambitious
unfinished run: never risk the artifacts you already verified.

## Ground rules
- Declared plan hashes are the unit of approval: state `plan_sha256 <64hex>` when you commit to a plan of work in your session text.
- Cite file paths + command outputs, not memory.
- If a gate tool contradicts your expectation, THAT is a finding — record before fixing.
