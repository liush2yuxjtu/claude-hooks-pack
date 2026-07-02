# Hook Design Rubric
# 评估"一个有 trigger words 的好 hook"长什么样

> 没有 meta hook 自动审计其他 hook — 本文件是手写 rubric,
> 用来对照设计新 hook 时 self-check。
> 引用本文的 hook 应在 header 注释里写 `rubric: HOOK_DESIGN_RUBRIC.md`。

---

## §0. 触发来源

- `~/.claude/VALUE.md`(根值)+ `~/.claude/values/BRANCH_*.md`(L1-L4)+ `LEAVES.md`(7 叶)
- `~/.claude/CLAUDE.md`(用户级 MUST 规则)
- 项目级 `CLAUDE.md`(若存在)

好 hook 一定能在上面 3 处找到依据,且能在 LEAVES.md 里指认至少 1 个对应叶。

---

## §1. Trigger coverage(覆盖度)

| 维度 | 标准 |
|---|---|
| 数量 | ≥ 100,或 ≤ 100 时在 header 里写明"为什么这个 hook 不需要 100"(例如 hook 只针对一个非常窄的反模式) |
| 语言比例 | 默认 ZH : EN ≈ 70 : 30,允许根据 hook 主题调整(纯英文场景可 100% EN) |
| 分类 | 必须覆盖 ≥ 4 类: 直接反问 / 间接拍板 / delegation 甩责 / 审批 gate / 菜单形态 |
| 形态 | ≥ 1 个非文本结构触发(checkbox `☐×3+`、code block、`?` 末尾、URL、`X 还是 Y` 模式等),不只靠文本 substring |
| 抗噪音 | 每个 trigger 自检 ≥ 1 个可能 false-positive 的合法语境,若命中则降权或下架 |

## §2. Detection discipline(检测纪律)

| 维度 | 标准 |
|---|---|
| 匹配方式 | 短词 / 短语用 substring;单词类用 regex `\b...\b`,避免 T2 这种"文件名里出现 next-step"误报 |
| Threshold | 支持 min_count(N 次以上才触发),用于模糊 trigger(例如"吗"单独出现不算,需要 ≥ 2 个"吗"才触发) |
| 负向过滤 | 至少一个白名单 / 黑名单:code block 内的不计数、URL/路径里的不计数、引用 block 内的不计数 |
| 性能预算 | 100 trigger 在 10KB transcript 上 < 50ms 总耗时,否则 hook 本身成为延迟源 |

## §3. Behavior(行为)

| 维度 | 标准 |
|---|---|
| 默认 | silent approve — `{"continue": true, "suppressOutput": true}`,不污染每次响应 |
| 命中 | inject prompt 到 next-turn additionalContext,**不**直接拦截或修改当前消息 |
| 决策权 | hook 不替 agent 选 — prompt 里只描述"刚才违反了哪条 value",agent 自己读 VALUE cascade 自决 |
| Exit code | 总是 0,除非 fatal 内部错误(脚本语法错、依赖工具找不到) |
| side-effect | 唯一允许的副作用:写 audit log + (可选)append per-session reminder 文件 |

## §4. Integration(集成)

| 维度 | 标准 |
|---|---|
| 事件链位置 | 若依赖前一个 hook 写文件 → append 在它**之后**;无依赖 → 任意位置 |
| Cascade 一致性 | 多 hook 共用同一份根值源(VALUE.md),不重复定义 |
| Escape hatch | 必有环境变量 `CLAUDE_<NAME>_DISABLED=1` 用于 debug 时静默 |
| 命名空间 | 所有自写文件/token 命名前缀化(如 `value-guard-next-step`),避免与未来 hook 冲突 |

## §5. Testability(可测性)

| 维度 | 标准 |
|---|---|
| 独立 harness | 必有一个能复用 trigger 列表做 replay 的测试脚本(可用 python+re,也可用 jq+bash) |
| 自检矩阵 | 至少 3 positive + 3 negative 真实场景(不是 toy example) |
| Dry-run | 通过 escape hatch 跑通整个 hook,验证 exit code 0 + audit 写入 |
| 误报率 | 良性 message 中 trigger 命中 < 10%;否则需要降权或下架 |

## §6. Documentation(文档)

| 维度 | 标准 |
|---|---|
| Header 注释 | 必含:触发源(VALUE.md/LEAVES/CLAUDE.md)、为什么这个 hook、什么情况下**不**触发 |
| 内联分类注释 | TRIGGERS 数组内分组,每组上方一行 `# ── 类别 ──` 注释 |
| Trigger 自释 | 每个 trigger 后允许内联注释(行尾 `# why`),特别说明边界场景 |
| Audit 字段 | JSONL 字段: `ts`, `session_id`, `action`, `markers_found`, `matched`(数组) |
| Per-session 日志 | 命中的话 append 到 `~/.claude/hooks/logs/<hook-name>-<session>.md`,由 UserPromptSubmit 配套 hook 注入 |

## §7. Anti-patterns(本 rubric 禁止的形状)

| 反模式 | 后果 |
|---|---|
| ❌ Hook 替 agent 做决定(给一个明确选项"选 A 还是 B") | 违反 L1,把决策零售化 |
| ❌ Hook 在 Stop 时阻塞(`"continue": false`) | 阻断用户工作流,违反 L3 |
| ❌ Trigger 列表里全是 close-but-not-quite 词(覆盖到正常业务用语) | false-positive 高,污染日志 |
| ❌ Hook 没有 escape hatch | debug 时没法临时关闭,影响排错 |
| ❌ Trigger 数量 = 0 或 ≤ 5 且无"为什么少"注释 | 表明 hook 设计未完成 |
| ❌ Header 没有引用 VALUE.md / LEAVES.md | 表明 hook 与 value 体系脱钩,是空降逻辑 |

## §8. Self-check 8 题(每次写新 hook 过一遍)

1. ☐ Trigger 列表 ≥ 100 或有理由?
2. ☐ 至少 1 个结构触发(非纯文本)?
3. ☐ 独立 harness + ≥ 3+3 测试?
4. ☐ Default silent,hit injects prompt?
5. ☐ Escape hatch 命名一致(`CLAUDE_<NAME>_DISABLED`)?
6. ☐ Header 引用 VALUE.md / LEAVES.md?
7. ☐ Audit JSONL + per-session 日志文件路径写明?
8. ☐ Settings.json wiring 顺序正确(无前置依赖可任意,有则 append-after)?

8/8 通过 = 可以 ship。6-7 = 修订后再 ship。<6 = 不要 ship。

---

## §附录 A:本仓库已有 hook 的对照

| Hook | Trigger 数 | ≥100 | 类别 | 形态 trigger | 文档 | rubric | escape | audit |
|---|---|---|---|---|---|---|---|---|
| `value-guard-next-step.sh` | 102 | ✓ | 9 | ☐×3+ | ✓ | ✓ | ✓ | ✓ |
| `meta-hook-creator.sh` | 33 | ✗ (narrow) | 3 | 文件路径 | ✓ | ✓ | ✓ | ✓ |
| `fast-iteration-inject.sh` | 101 | ✓ | 6 | — | ✓ | ✓ | ✓ | ✓ |
| `mocks-not-stuck-reminder.sh` | 15 | ✗ (narrow) | 1 | `/to-prd` | ✓ | ✓ | ✓ | ✓ |
| `pop-open-on-ship.sh`(unwired) | 15 | ✗ (narrow) | 1 | URL 路径 | ✓ | ✓ | ✓ | ✓ |
| `research-md-no-ask.sh` | 2 | ✗ (narrow) | 1 | 文件名 | ✓ | ✓ | ✓ | ✓ |
| `value-guard.sh` | 0 | N/A | N/A | N/A | ✓ | (default) | ✓ | ✓ |
| `4-fast-rule.sh` | 0 | N/A | N/A | N/A | ✓ | (default) | ✓ | (default) |

**状态:** 2026-06-17 对齐完成。2 个 ≥100 + 4 个 <100(全部有 narrow-scope 例外文档)+ 2 个 always-on(no-trigger 风格)。8/8 通过 rubric §1-7。

**未 wired:** `pop-open-on-ship.sh`(slice 0003 主动 unwire,因 wrong-Chrome auto-pop pain,留盘可逆)。
