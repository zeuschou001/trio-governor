#!/usr/bin/env bash
set -euo pipefail

REPO_ABS=$(cd "$(dirname "$0")/.." && pwd)

SKILL="$REPO_ABS/skills/trio-orchestrator/SKILL.md"
DEV="$REPO_ABS/commands/trio/dev.md"
QUICK="$REPO_ABS/commands/trio/quick.md"

for f in "$SKILL" "$DEV" "$QUICK"; do
  [ -f "$f" ] || { printf '缺失文件: %s\n' "$f" >&2; exit 1; }
done

python3 - "$SKILL" "$DEV" "$QUICK" <<'PY'
import math, re, sys

def tokens(path: str) -> int:
    s = open(path, 'r', encoding='utf-8').read()
    ascii_n = sum(1 for c in s if ord(c) <= 0x7F)
    cjk_n = len(s) - ascii_n
    return math.ceil(ascii_n / 4 + cjk_n * 1.5)

skill, dev, quick = sys.argv[1], sys.argv[2], sys.argv[3]
t_skill = tokens(skill)
t_dev = tokens(dev)
t_quick = tokens(quick)
t_cmd = t_dev + t_quick
total = t_skill + t_dev + t_quick

blocklist_tokens = 0
try:
    src = open(skill, 'r', encoding='utf-8').read()
    m = re.search(r'## gstack blocklist[^\n]*\n+```[^\n]*\n(.*?)\n```', src, re.S)
    if m:
        blob = m.group(1)
        a = sum(1 for c in blob if ord(c) <= 0x7F)
        c = len(blob) - a
        blocklist_tokens = math.ceil(a / 4 + c * 1.5)
except Exception:
    pass

print(f'SKILL.md                  = {t_skill} token (reference 1800)')
print(f'commands/trio/dev.md      = {t_dev} token')
print(f'commands/trio/quick.md    = {t_quick} token')
print(f'commands 合计              = {t_cmd} token (reference 250)')
print(f'blocklist 内嵌            = {blocklist_tokens} token (reference 300)')
print(f'-----')
print(f'总计                      = {total} token (reference 2600 / 4000)')

depth2 = 0
try:
    for line in open(skill, 'r', encoding='utf-8'):
        if re.match(r'^###\s+Step\b', line) or re.match(r'^##\s+Step\b', line):
            depth2 += 1
except Exception:
    pass
if depth2 > 0:
    print(f'警告: 疑似内嵌外部 skill 细节(检测到 {depth2} 处 Step 子步骤),请改为跳转引用', file=sys.stderr)

sys.exit(0)
PY
