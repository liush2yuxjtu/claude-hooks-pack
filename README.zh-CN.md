# claude-hooks-pack(中文)

> 27 个用户级 Claude Code hook 的可分发包(5 个生命周期事件)+ 设计规范 + 一键安装/卸载脚本。
>
> English version: [README.md](./README.md)

---

## 这是什么

把 `~/.claude/hooks/`(本机上的用户级 Claude Code hooks 目录)原样打包,任何 macOS / Linux 机器克隆后跑 `bash install.sh` 就能在 2 分钟内恢复全部 hook 接线(`~/.claude/settings.json` 里的 `hooks{}` 块)。

**包含 27 个 active hook + 3 个 dormant hook + 1 个子包(`fix-uat-env/`)+ 设计文档。**

## 安装

```bash
git clone https://github.com/liush2yuxjtu/claude-hooks-pack.git
cd claude-hooks-pack
bash install.sh                # 复制 hook + 合并 settings.json
bash install.sh --dry-run      # 预览,不做任何写入
bash install.sh --no-settings  # 只复制 hook 文件,不碰 settings.json
```

`install.sh` 会做 3 件事:

1. 把 `./hooks/` 下所有 `.sh` / `.py` 复制到 `~/.claude/hooks/`。
2. 备份你现有的 `~/.claude/settings.json` 到 `settings.json.bak-<UTC>`,然后从 `./settings/hooks.fragment.json` 合并 `hooks` 块进去。
3. 把 `redlines.tsv`(被 `guard.sh` 消费)复制到 `~/.claude/hooks/`。

装完后重启 claude-code(或开新会话)即生效。

## 卸载

```bash
bash uninstall.sh
```

从最新一份备份恢复 `settings.json`,并删除本包装过的所有 hook 文件。

## 目录结构

```
claude-hooks-pack/
├── README.md / README.zh-CN.md   # 双语 README
├── LICENSE                        # MIT
├── install.sh / uninstall.sh     # 一键装/卸
├── hooks/                         # 27 active + 3 dormant + 1 子包
│   ├── 4-fast-rule.sh / capture-session-name.py / clash-mode-guard.sh
│   ├── done-find-downloads.sh / fast-iteration-inject.sh / finish-not-defer.sh
│   ├── fix-uat-env/               # 子包(hook.sh + apply.sh + test.sh + README.md)
│   ├── followup-not-ask.sh / followup-spawn-agents.sh / force-playwright-cli.sh
│   ├── guard.sh / honest-report-gate.sh / keep-going.sh / meta-hook-creator.sh
│   ├── mocks-not-stuck-reminder.sh / no-ask-file-followups.sh
│   ├── pair-chrome-soft-gate.sh / playwright-headless.sh
│   ├── pop-open-on-ship.sh        [dormant]
│   ├── reap-orphan-chrome.sh / reap-orphan-chrome.solution.sh [dormant, reference]
│   ├── research-md-no-ask.sh / self-report-fused.sh.retired [dormant]
│   ├── selfhost-browser-no-ask.sh / spawn-not-ask.sh
│   ├── straight-fix-no-ask.sh / value-guard-next-step.sh
│   ├── value-guard.sh / value-inject.sh / winbrain-gitlab-push.sh
├── docs/
│   ├── HOOK_DESIGN_RUBRIC.md     # 设计规范(8 章 + 8 题自检)
│   └── value-guard-template.md   # VALUE-cascade 提示词模板
├── settings/hooks.fragment.json  # 要合进 settings.json 的 hooks 块
├── data/redlines.tsv             # guard.sh 用的 redline 表
└── test/straight-fix-no-ask.test.sh  # §5 规范的测试 harness
```

---

## 27 个 active hook 速查表

> 想让 LLM 帮你逐个解释 + 选择性安装?直接复制下面这段提示词发给它:

```
请你帮我git clone https://github.com/liush2yuxjtu/claude-hooks-pack 到/temp然后告诉我每一个hook都是干啥的，让我选择性的安装。
```

### SessionStart(1)

| Hook | 作用 |
|---|---|
| `capture-session-name.py` | 把当前 session 标识抓进 `state/`,供下游 hook 关联 |

### SubagentStart(1)

| Hook | 作用 |
|---|---|
| 内联 `echo` | 给 spawn 的子 agent 注入 `CLAUDE_REDLINE_ENFORCE=1` 环境变量 |

### UserPromptSubmit(10)— 你每次发消息时触发

| Hook | 触发条件 | 作用 |
|---|---|---|
| `mocks-not-stuck-reminder.sh` | 提到 `/to-prd` / 计划 / 拆 issue | 提醒:用 mock 解锁下游并行 agent,别等真实 A 完成 |
| `research-md-no-ask.sh` | 提到 `_RESEARCH.md` | 禁止问"要不要 commit / 删掉"研究文件,默认不动 |
| `spawn-not-ask.sh` | "下一步要不要 / 应该怎么走" | 提示:直接 spawn 后台 subagent,别问用户 |
| `fast-iteration-inject.sh` | "1 天 / 2 小时 / no-HITL / 客户反馈" | 把速度 + 发货 + 反馈延迟信号注入本轮上下文 |
| `selfhost-browser-no-ask.sh` | 自部署 / 浏览器 e2e / 内网 | 提示:用对的浏览器模式直接干活,别问 |
| `value-inject.sh` | always-on | 读 Stop 写入的 per-session reminder,注入 `additionalContext` |
| `reap-orphan-chrome.sh` | 关键词 | 指针:孤儿 Chrome 让 agent 跑 `reap-orphan-chrome.solution.sh` |
| `pair-chrome-soft-gate.sh` | 浏览器 / UAT / 可见 Chrome | 软提示:走 headless `playwright-cli` |
| `done-find-downloads.sh` | "Done / Finished / 搞定" | 把 `~/Downloads` 最新变动拉到本轮上下文 |
| `fix-uat-env/hook.sh` | UAT / 修环境场景 | 子包:自动修复坏掉的 UAT 环境变量 |

### PreToolUse(5)— 每次调用工具前触发

| 匹配器 | Hook | 作用 |
|---|---|---|
| `Bash` | `clash-mode-guard.sh` | **硬阻断** 任何改全局代理 / TUN / SOCKS 的命令 |
| `Bash\|Edit\|Write\|MultiEdit` | `guard.sh` | redline 引擎 — 命中 `redlines.tsv` 就 block |
| `mcp__plugin_playwright_playwright__.*` | `force-playwright-cli.sh` | 强制走 `playwright-cli` skill,不直接用 MCP |
| `Bash\|Skill` | `playwright-headless.sh` | 软门控:浏览器走 headless,别弹窗 |
| `Bash` | `winbrain-gitlab-push.sh` | win_brain 项目专属:GitLab push 重试经验 |

### Stop(10)— agent 每次停下时触发

| Hook | 触发条件 | 作用 |
|---|---|---|
| `4-fast-rule.sh` | always-on | 每次停都强化 4-FAST 速度规则 |
| `value-guard.sh` | always-on | 每次停都提醒:走 VALUE 自决链再问 HITL |
| `value-guard-next-step.sh` | 140 trigger 词 + ☐×3+ | 打脸"下一步菜单 / 要不要 / 等你说"反模式 |
| `meta-hook-creator.sh` | "创建 / 设计新 hook" | 注入 HOOK_DESIGN_RUBRIC §8 自检再写 |
| `followup-not-ask.sh` | "开 follow-up issue 吗?" | 禁止把残留问题甩成 follow-up |
| `followup-spawn-agents.sh` | 裸 "followup / follow up" | **阻断停止**,强制派并行 agent 解决 |
| `straight-fix-no-ask.sh` | "提议 / 留待下轮 / 要不要" | 打脸 ask-and-defer 结尾,逼同轮修 |
| `keep-going.sh` | checkpoint 式停顿 | 强制继续,直到 DOD / 硬阻塞 / 不可逆授权 |
| `honest-report-gate.sh` | "finished" + 闪烁其词 | 阻断不诚实的报告 |
| `finish-not-defer.sh` | "scope 缩减 / 留作增量" | 阻断把工作推到"下次增量" |

---

## 没接线的 3 个 dormant hook(默认不启用)

- `pop-open-on-ship.sh` — 2026-06 因 wrong-Chrome 自动弹窗体验问题主动 unwire
- `reap-orphan-chrome.solution.sh` — 参考脚本(非 hook 本身),agent 触发后手动跑
- `self-report-fused.sh.retired` — 已被 `value-guard*.sh` 家族取代

## 设计参考

- `docs/HOOK_DESIGN_RUBRIC.md` — 8 章规范 + 8 题自检,新 hook 必过
- `docs/value-guard-template.md` — VALUE 级联(root → L1-L4 → 7 leaves)提示词模板
- `data/redlines.tsv` — `guard.sh` 消费的 redline 表(TSV:`tool<TAB>regex<TAB>action<TAB>reason`)

## License

MIT,详见 `LICENSE`。