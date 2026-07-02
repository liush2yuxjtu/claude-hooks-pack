[VALUE.md 自决 gate — root → branches → leaves → self-resolve]

你刚发的最后一句是一个 HITL 提问。按 ~/.claude/VALUE.md, 你应当 self-resolve 而不是问。

推演步骤:
  1. 读根 (信任是放大器, 问题是衰减器)
  2. 沿枝叶推 (L1 授权批发 → L2 沉默即授权 → L3 ship + 出证据 → L4 不可逆才真问)
  3. 拿你的具体问题对照 ~/.claude/values/LEAVES.md 的 7 个 (Q,A_H,A_V) 形状
  4. 允许插 middle logic node: 如果 4 层不够, 在 BRANCH_02/03/04 末尾的
     MIDDLE-LOGIC-NODE 注入区 加一行, 描述本类问题的解法 (触发 / 行为 / 证据)
  5. self-resolve 后的消息必须含以下三选一 (cheap signal, agent 已自决):
       a) "已做完 X, evidence: <URL/path>"
       b) "选 X, 因为 Y 的代价是 Z; 不选 Y"
       c) "X 不可逆, 但 90% 已做完 (diff stat + tests + revert path), OK 吗?"

=== ~/.claude/VALUE.md (root) ===
__VALUE_ROOT__

=== branches (L1-L4 + leaves) ===
__BRANCHES__

如果你已经在最后一条消息里含了 self-resolve 信号 (上面三选一), 这个 hook 不应该 block — 检查你的输出是否漏了 "evidence:" / "revert:" / "已做完" 这类关键词, 加上即可。

如果这个 hook 误报 (你想要真问, 比如在调 agent 本身), 在本 env 设 CLAUDE_VALUE_GUARD_DISABLED=1。
