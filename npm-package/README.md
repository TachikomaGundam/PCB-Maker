# pcb-maker

PCB 设计智能体的**考卷和尺子**。本包不含任何 AI——它给你已有的 agent 环境发同一套题，并用同一个不信自报、独立复测的评分器打分。

## 包含

- `agents/` — 角色说明（总调度如何派发原理图/摆放/布线/铺铜/质检）
- `scenarios/` — 分阶段考卷：phase A（清单→原理图→摆放板）、phase B（布线+铺铜）
- `fixtures/` — 考题用的真实元件清单与规格（9 器件玩具板，含故意埋的坑）
- `grader.mjs`（安装后命令 `pcb-maker-grade`）— 评分器：拿你自己的 `kicad-cli` 复测考生工件（ERC/DRC/悬空线/陷阱点名），输出单行 JSON 分数

## 用法

```bash
# 考生把 board.kicad_sch / board.kicad_pcb / FINDINGS.md / RESULT.md 放进考场目录后：
PCB_FORCE_ARENA=/path/to/arena pcb-maker-grade r22-toy-phaseA scenarios/r22-toy-phaseA.md
```

需要 Node ≥ 20 与 `kicad-cli`（KiCad 8/10 实测；10 语法差异已在评分器内处理）。

## 评分哲学（一句话）

分数只来自**独立复测**：考生的成绩单不作数，考官自己重跑一遍才作数；诚实记录踩坑另给分（EYES 臂），所以"发现了什么"和"做对了什么"同样重要。

项目背景与进化流水账见 GitHub 仓库 `PCB-Maker`（PCB制作大师）。
