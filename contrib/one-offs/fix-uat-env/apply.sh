#!/usr/bin/env bash
# fix-uat-env apply.sh — idempotent env-patch script
# Called by the agent when /fix-uat-env hook fires.
# Re-running is safe. Logs every step to a timestamped file.
#
# rubric: HOOK_DESIGN_RUBRIC.md §5 (independent harness / dry-run)
# value-source: VALUE.md §L1 授权 / §L3 ship+证据
set -uo pipefail

REPO="${FIX_UAT_ENV_REPO:-$HOME/Documents/win-brain-mrs/winbrain-mr-middle-think/winbrain-src}"
LOG="$HOME/.claude/hooks/logs/fix-uat-env-apply-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "=== fix-uat-env apply.sh — repo=$REPO — $(date -u +%FT%TZ) ==="

if [[ ! -d "$REPO" ]]; then
  echo "ERROR: repo not found at $REPO. Set FIX_UAT_ENV_REPO env var." >&2
  exit 1
fi

cd "$REPO" || {
  echo "ERROR: cannot cd to $REPO" >&2
  exit 1
}

# --- Step 1: scripts/serve.sh forwards DEER_FLOW_AUTH_DISABLED_USER_EMAIL ---
SERVESH="scripts/serve.sh"
if [[ -f "$SERVESH" ]]; then
  if grep -q 'DEER_FLOW_AUTH_DISABLED_USER_EMAIL' "$SERVESH"; then
    echo "[1/4] $SERVESH already forwards DEER_FLOW_AUTH_DISABLED_USER_EMAIL — no-op"
  else
    # Find the DEV_AUTH_ENV line and append the email forwarding block
    # The block matches what we already pushed in commit feb31f84
    if grep -q 'DEV_AUTH_ENV="DEER_FLOW_AUTH_DISABLED=\$DEV_AUTH_DISABLED_VALUE DEER_FLOW_DISABLE_AUTH=\$DEV_DISABLE_AUTH_VALUE"' "$SERVESH"; then
      # Use python for atomic patch (sed range with newline is fragile)
      python3 - <<'PYEOF'
from pathlib import Path
p = Path("scripts/serve.sh")
src = p.read_text()
old = '    DEV_AUTH_ENV="DEER_FLOW_AUTH_DISABLED=$DEV_AUTH_DISABLED_VALUE DEER_FLOW_DISABLE_AUTH=$DEV_DISABLE_AUTH_VALUE"'
new = old + '\n' + '''    # Forward the optional impersonation email so the dev user greeting shows
    # the real name instead of always defaulting to e2e@example.com.
    if [ -n "${DEER_FLOW_AUTH_DISABLED_USER_EMAIL:-}" ]; then
        DEV_AUTH_ENV="$DEV_AUTH_ENV DEER_FLOW_AUTH_DISABLED_USER_EMAIL=$DEER_FLOW_AUTH_DISABLED_USER_EMAIL"
    fi'''
if old in src and "DEER_FLOW_AUTH_DISABLED_USER_EMAIL=$DEER_FLOW_AUTH_DISABLED_USER_EMAIL" not in src:
    p.write_text(src.replace(old, new))
    print("[1/4] patched scripts/serve.sh — forwarding DEER_FLOW_AUTH_DISABLED_USER_EMAIL")
else:
    print("[1/4] scripts/serve.sh — no patch needed (already patched or block not found)")
PYEOF
    else
      echo "[1/4] WARN: DEV_AUTH_ENV anchor not found in $SERVESH — manual review needed"
    fi
  fi
else
  echo "[1/4] SKIP: $SERVESH not present (not a win_brain checkout?)"
fi

# --- Step 2: config.local.yaml agents_api.enabled: true ---
CFG="config.local.yaml"
if [[ -f "$CFG" ]]; then
  if grep -E '^\s*agents_api:' -A1 "$CFG" | grep -q 'enabled: true'; then
    echo "[2/4] $CFG already has agents_api.enabled: true — no-op"
  else
    python3 - <<'PYEOF'
from pathlib import Path
p = Path("config.local.yaml")
src = p.read_text()
# Find "agents_api:" and ensure next non-comment line has enabled: true
lines = src.splitlines(keepends=True)
out = []
in_block = False
patched = False
for i, line in enumerate(lines):
    if line.strip().startswith("agents_api:"):
        in_block = True
        out.append(line)
        continue
    if in_block and line.strip().startswith("enabled:"):
        out.append("  enabled: true\n")
        patched = True
        in_block = False
        continue
    if in_block and line.strip() and not line.lstrip().startswith("#"):
        # next top-level key reached; insert enabled:true before
        out.append("  enabled: true\n")
        patched = True
        in_block = False
    out.append(line)
if not patched:
    # append a fresh block
    out.append("\nagents_api:\n  enabled: true\n")
p.write_text("".join(out))
print("[2/4] patched config.local.yaml — agents_api.enabled: true")
PYEOF
  fi
else
  echo "[2/4] SKIP: $CFG not present"
fi

# --- Step 3: ensure zhangqing-group extensions_config.json has FMCG skills enabled ---
GROUP_DIR="backend/.deer-flow/groups/zhangqing-group"
GROUP_CFG="$GROUP_DIR/extensions_config.json"
mkdir -p "$GROUP_DIR"
if [[ -f "$GROUP_CFG" ]]; then
  echo "[3/4] $GROUP_CFG exists — checking FMCG skills enabled"
  # Idempotent: set all skills.enabled = true (don't disable anything user disabled)
  python3 - <<'PYEOF'
import json
from pathlib import Path
p = Path("backend/.deer-flow/groups/zhangqing-group/extensions_config.json")
data = json.loads(p.read_text())
skills = data.setdefault("skills", {})
fmcg = ["rd-overall-diagnosis", "store-diagnosis", "category-benchmark",
        "category-diagnosis", "category-kpi", "category-trend",
        "distribution-quality", "giv-category-summary", "hub-performance",
        "product-line-metrics", "store-coverage-metrics", "store-execution-quality"]
toggled = []
for name in fmcg:
    if name in skills and not skills[name].get("enabled", False):
        skills[name]["enabled"] = True
        toggled.append(name)
if toggled:
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"[3/4] enabled FMCG skills: {toggled}")
else:
    print("[3/4] all FMCG skills already enabled (or absent) — no-op")
PYEOF
else
  # Bootstrap with all FMCG skills enabled
  python3 - <<'PYEOF'
import json
from pathlib import Path
p = Path("backend/.deer-flow/groups/zhangqing-group/extensions_config.json")
p.parent.mkdir(parents=True, exist_ok=True)
data = {"mcpServers": {}, "skills": {}}
fmcg = ["rd-overall-diagnosis", "store-diagnosis", "category-benchmark",
        "category-diagnosis", "category-kpi", "category-trend",
        "distribution-quality", "giv-category-summary", "hub-performance",
        "product-line-metrics", "store-coverage-metrics", "store-execution-quality"]
for name in fmcg:
    data["skills"][name] = {"enabled": True}
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print(f"[3/4] bootstrapped {p} with {len(fmcg)} FMCG skills enabled")
PYEOF
fi

# --- Step 4: ensure fmcg-diagnosis-test agent SOUL.md exists ---
AGENT_DIR="backend/.deer-flow/agents/fmcg-diagnosis-test"
AGENT_SOUL="$AGENT_DIR/SOUL.md"
if [[ -f "$AGENT_SOUL" ]]; then
  echo "[4/4] $AGENT_SOUL exists — no-op"
else
  mkdir -p "$AGENT_DIR"
  cat >"$AGENT_SOUL" <<'SOUL'
# fmcg-diagnosis-test

你是 WinBrain 的 FMCG 诊断 test agent(挂在张晴 group 下)。

## 能力

- 拉取 FMCG 数据库(品类、SKU、门店、销售、促销、库存)
- 跑 rd-diagnosis 流程:业务健康筛查 / 问题归因 / 门店执行 / 综合建议 四段
- 输出 4 个稳定 `##` section:`业务健康筛查` / `问题归因判断` / `门店执行诊断` / `综合行动建议`
- 必须 call `save_fmcg_report_markdown` 落盘到 `/mnt/user-data/outputs/` 并 emit 4 段

## 行为约定

- 默认中文回复,数据驱动
- 工具调用前先 emit `SESSION INTENT:` 段,把计划步骤列给用户
- plan_mode 必须开启(`is_plan_mode: True` + TodoList middleware)
- 长任务用 write_todos 工具推 TODO,前端 To-dos 卡会实时渲染

## 边界

- 只能读 FMCG DB 标记为 readonly 的视图
- 写操作走 save_fmcg_report_markdown 单点出口
SOUL
  echo "[4/4] created $AGENT_SOUL"
fi

# --- final: report ---
echo "=== apply.sh done — log: $LOG ==="
