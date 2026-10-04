# scenario r19-toy-endToEnd

## Brief
你被给定一个隔离工作区（当前目录）。用 `tools/` 里的工具链把 `spec.json`（9 器件/8 网，含 NC 网络）
变成一块通过验收的 KiCad 10 板。原始设计简报在 `esp32s3-r12-BRIEF.txt`（背景材料；网表以 spec.json 为准）。

必须产出的文件（全部在当前目录）：
1. `out.kicad_sch` — 原理图；`GATES.md` 记录 ERC 0/0 与网表往返逐网精确全等的证据。
2. `out.kicad_pcb` — 放置+布线+铺铜完成态。
3. `fab-out/` — Gerber、钻孔、贴片机坐标。
4. `FINDINGS.md` — 你踩到的每一个问题：症状/根因/修法/复验命令。清单完整性比速度重要。
5. `RESULT.md` — 产物路径 + 每项门禁的真实数字（贴命令输出；评审会原样重跑你的命令）。

终态验收（由 `kicad-cli pcb drc <board> --refill-zones --save-board --format json --severity-error` 判定）：
- 非 starved_thermal 的 DRC 错误 = 0
- 非 NC 网络的 ratsnest 间隙 = 0
- starved_thermal 允许存在，但必须在 FINDINGS.md 给出根因分析

纪律：只准写当前工作区；工件写完必须回读磁盘核实；长步骤增量落盘（每完成一边就把铜皮写进
progress 文件再续），进程被杀不许丢已完成的工作；诚实失败好过虚假通过。
