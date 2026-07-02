#!/usr/bin/env bash
# force-playwright-cli.sh — user-level PreToolUse hook
# 拦截 plugin:playwright:playwright MCP tool 调用，强制改用 /playwright-cli skill。
# 触发的工具名前缀: mcp__plugin_playwright_playwright__*
# 退出码: 0=放行, 2=阻断并把 stderr 作为拒绝原因回显给 Claude。

set -euo pipefail

payload="$(cat)"

# 解析 tool_name,失败则放行(避免 hook 自身故障影响主流程)。
tool_name="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_name", ""))
except Exception:
    print("")
' 2>/dev/null || true)"

if [[ "$tool_name" == mcp__plugin_playwright_playwright__* ]]; then
  short="${tool_name#mcp__plugin_playwright_playwright__}"
  cat >&2 <<EOF
[force-playwright-cli] 禁止调用 plugin:playwright:playwright MCP tool \`$short\`。

请改用 /playwright-cli skill (通过 Bash 执行 \`playwright-cli <cmd>\`):

    playwright-cli open <url>          # 打开浏览器
    playwright-cli goto <url>          # 跳转
    playwright-cli snapshot            # 拿到 ref + a11y 树
    playwright-cli click <ref>         # 按 ref 点
    playwright-cli fill <ref> "<val>"  # 填表单
    playwright-cli type "<text>"       # 模拟键入
    playwright-cli screenshot [--filename <path>] [--full-page]
    playwright-cli resize <w> <h>      # 改视口
    playwright-cli close               # 关闭
    playwright-cli console <level>     # 取 console 日志
    playwright-cli network [filter]    # 取网络请求

skill 详情: ~/.claude/skills/playwright-cli/SKILL.md
EOF
  exit 2
fi

exit 0
