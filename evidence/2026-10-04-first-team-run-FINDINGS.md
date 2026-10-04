# FINDINGS — r22-toy-phaseA (append-only defect ledger)

Format: F-NNN | time | symptom / root cause / decision + evidence. Newest appended at end. Never edited retroactively.

---

**F-001 | 2026-10-04T14:28Z | Mission input BRIEF.txt absent from filesystem.**
Symptom: mission declares `spec.json` + `BRIEF.txt` "already in the arena"; `find /home/lab -name 'BRIEF*'` → 0 results.
Root cause: launcher seeded only the spec; r19 TASK.md likewise referenced `esp32s3-r12-BRIEF.txt` which is also missing from `internal-arena/r19/`.
Decision: spec.json declares itself authoritative ("the component/netlist spec (authoritative)") and is self-contained (9 refs, full pin maps, footprint names, deviation notes). BRIEF.txt is background material only → proceed without it. Recorded, not blocking.

**F-002 | 2026-10-04T14:28Z | No r22 arena directory exists.**
Symptom: `find /home/lab/workspace/pcb-control -maxdepth 4 -iname '*r22*'` → 0 hits; workspace root (`production-console`, cwd, git repo) contains no spec.json.
Root cause: mission text uses "the arena" loosely; the only fixture spec is `/home/lab/workspace/pcb-control/internal-arena/r19/spec.json`, board name `"toy-m2"` — matches mission id `r22-toy-phaseA`; its `_provenance` cites `esp32s3-r12-BRIEF.txt` (F-001's missing file).
Decision: adopt `/home/lab/workspace/pcb-control/internal-arena/r19/spec.json` (schema_version 1.0, 9 components) as authoritative input, read-only. Deliverables at repo/workspace root `/home/lab/workspace/pcb-control/production-console/` per mission ("repo/workspace root").

**F-003 | 2026-10-04T14:28Z | `PCB_PROJECT_ROOT` env unset in this session.**
Symptom: `echo $PCB_PROJECT_ROOT` → empty; charter paths assume it is launcher-exported.
Decision: resolved explicitly — control-plane evidence roots = `/home/lab/workspace/pcb-control/{dispatches,state,reports}` (per prior-round receipts), working root = `production-console/` git repo.

**F-004 | 2026-10-04T14:52Z | Board-round children cannot write the plan-declared workspace-root deliverables directly.**
Symptom: plan scope listed production-console/board.kicad_* as write targets; but plugin `pcb-control-plane.ts:2085` admits PCB_PROJECT_ROOT only under PCB_DISPATCH_ALLOWED_ROOTS (env empty) → default `/home/lab/workspace/pcb-control/fixtures`; `:974` board-round allowance for pcb-candidate-writer = [pcb-control/candidate, pcb-control/fixtures]. production-console is outside both → RM-2 checkpoint would roll it back (ROLLED_BACK + TREE_OUT_OF_SCOPE_WRITE).
Decision: execution model = children author/stage board artifacts under `/home/lab/workspace/pcb-control/fixtures/r22-arena/` (working root seeded with spec.json); orchestrator runs the deterministic gate commands (kicad-cli is the gate tool; agent self-report is not evidence, and per r16-B matrix `bash` is false in every child session anyway); verified board files are then mechanically relayed (byte-identical cp, sha256-stamped) to production-console root per §5 exception 1. FINDINGS/RESULT ledger relay likewise; .state/workflow.md dispatch log maintained.

**F-005 | 2026-10-04T14:52Z | Wall-budget pressure.**
Mission budget ≈25 min; input reconciliation + plan gate + approval consumed ~26 min (14:24 start). Mitigation: compress dispatch rounds — 1 discovery + up to 2 writer rounds (sch, pcb) + verifier, parallelize gate measurement immediately after each write round; commit deliverables incrementally; never regenerate passing artifacts.

**F-006 | 2026-10-04T14:58Z | INFRA: dispatch receipt write fails EROFS (child still launched, request consumed).**
Symptom: pcb_dispatch(r22-disc1) returned `EROFS: read-only file system, open '/home/lab/workspace/harness/PCB-Agent/reports/recovery/dispatches/pcb-dispatch-r22-disc1.json'`; but `/home/lab/workspace/pcb-control/dispatches/pcb-dispatch-r22-disc1.json.consumed` exists and child session ses_efcfafb09ffe0szHQpSA2eXKtK (agent=pcb-discovery, parent=ses_efd105c58ffejBmSgnzpXfb7Ci) was created per OPENCODE_DB.
Root cause: RECEIPT_DIR volume /home/lab/workspace/harness is read-only in this bench instance (mount lacks write bit for user lab).
Decision: classified INFRA_FAIL (environment, not design/binding). Binding chain itself verified up to the receipt write: plan_sha256 + approval_message_id msg_102fc7d1c001WG5IRSE3kT5PdW resolved (else no child, per :941 resolveApproval pre-child). Child result text remains auditable from the session DB; receipt absence noted in dispatch log. Do NOT block Phase A on it; no re-dispatch (child live).

**CORRECTION (clock) | appended 2026-10-03T18:45Z |** entries F-001..F-006 were labeled with local wall time (~UTC+8 offset); authoritative UTC of those events is F-001..003 ≈ 2026-10-03T18:05–18:16Z, F-004..005 ≈ 18:22Z, F-006 ≈ 18:34Z. Ledger content unchanged; append-only correction of timestamps only.

**F-007 | 2026-10-03T18:45Z | BLOCKER resolved by documented alias map: J1 spec pins 1..16 vs USB4110 real pads A1..B12+SH (discovery FINDING-3).**
Evidence: `grep '(pad' .../Connector_USB.pretty/USB_C_Receptacle_GCT_USB4110.kicad_mod` → A1,A4,A5,A6,A7,A8,A9,A12,B1,B4,B5,B6,B7,B8,B9,B12,SH (+2 np_thru_holes). spec.json:48-69 numbers them 1..16.
Decision (fixture-convention, mirrors spec.json's own U1 convention declaration): canonical alias map = spec ordinal k ↔ pad[k] of ordered list [A1,A4,A5,A6,A7,A8,A9,A12,B1,B4,B5,B6,B7,B8,B9,B12]; shell pad SH has no spec pin → left unconnected (warning-class only, recorded). Schematic J1 symbol authored with ACTUAL pad names; netlist roundtrip compares net membership AFTER alias normalization. Real footprint used for placement (mission: "real footprints").

**F-008 | 2026-10-03T18:45Z | U1 footprint/symbol pin-count asymmetry: footprint pads 1..41, spec maps 1..21 only (F-004).**
Decision: schematic symbol U1 embeds exactly spec pins 1..21; pads 22..41 remain unconnected on board (ratsnest rows tolerated; "pad not in symbol" is warning severity — to be MEASURED at gate, not assumed). Also symbol-library substitutions per discovery FINDING-7: MPN ESP32-S3-WROOM-1-N8R8→RF_Module:ESP32-S3-WROOM-1; ME6211C33→no exact symbol (ME6211C33M5 exists but SOT-23 w/ diff pin names; pin-1=FBD vs spec pin-1=+5V_IN CONVENTION CONFLICT) and USB4110 symbol absent → DECISION: author ALL nine refs as fixture-custom embedded symbols with pin numbers == footprint pad names and net assignment == spec (alias-mapped for J1). Library pin-name metadata is cosmetic; net membership + pad identity are what gates measure.

**F-009 | 2026-10-03T18:45Z | Plan revision (budget, per F-005): merge plan steps 2+3 into ONE pcb-candidate-writer dispatch (schematic then placement, incremental writes under fixtures/r22-arena/ per F-004 execution model).** Children lack bash (r16-B matrix) → gate MEASUREMENT runs in orchestrator bash lane after each writer round; error lists fed back to fix rounds (max 3).
