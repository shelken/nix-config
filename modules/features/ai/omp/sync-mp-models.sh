#!/usr/bin/env bash
# 从 magpie /v1/models 差集同步 mp provider 的 modelOverrides
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_FILE="${SCRIPT_DIR}/models.yml"

# 1. 提取 mp 的 baseUrl 与 apiKey
BASE_URL=$(awk '/^  mp:/ { in_mp = 1 } in_mp && /baseUrl:/ { print $2; exit }' "$MODELS_FILE")
API_KEY=$(awk '/^  mp:/ { in_mp = 1 } in_mp && /apiKey:/ { print $2; exit }' "$MODELS_FILE")

if [ -z "$BASE_URL" ]; then
  echo "Error: 未在 models.yml 找到 mp 的 baseUrl" >&2
  exit 1
fi

AUTH_HEADER=()
if [ -n "$API_KEY" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${API_KEY}")
fi

MP_JSON=$(mktemp)
OMP_JSON=$(mktemp)
BLOCK_FILE=$(mktemp)
BASE_DIR=$(mktemp -d /tmp/omp-agent-XXXXXX)
trap 'rm -f "$MP_JSON" "$OMP_JSON" "$BLOCK_FILE" "$BASE_DIR"/* 2>/dev/null || true; rmdir "$BASE_DIR" 2>/dev/null || true' EXIT

# 2. 获取 magpie 最新 /v1/models
if ! curl -sf -m 10 "${AUTH_HEADER[@]}" "${BASE_URL}/models" -o "$MP_JSON"; then
  echo "Error: 无法从 ${BASE_URL}/models 获取模型列表" >&2
  exit 1
fi

# 3. 测量 omp 的原生发现能力（剥离已生成的同步块，避免自引用振荡）
if command -v omp >/dev/null 2>&1; then
  sed '/# >>> mp-modelOverrides:auto-sync >>>/,/# <<< mp-modelOverrides:auto-sync <<</ {
    /# >>> mp-modelOverrides:auto-sync >>>/! {
      /# <<< mp-modelOverrides:auto-sync <<</!d
    }
  }' "$MODELS_FILE" > "${BASE_DIR}/models.yml"
  PI_CODING_AGENT_DIR="$BASE_DIR" omp models mp --json > "$OMP_JSON" 2>/dev/null || echo '{"models":[]}' > "$OMP_JSON"
else
  echo '{"models":[]}' > "$OMP_JSON"
fi

# 4. 用 jq 对比差集并生成 YAML 格式的 modelOverrides
JQ_BIN="$(command -v jq 2>/dev/null || echo "/run/current-system/sw/bin/jq")"

# shellcheck disable=SC2016
OVERRIDES=$("$JQ_BIN" -r -n \
  --slurpfile mp "$MP_JSON" \
  --slurpfile omp "$OMP_JSON" '
  ($omp[0].models | INDEX(.id)) as $cur |
  ["minimal","low","medium","high","xhigh","max"] as $valid_efforts |
  [
    $mp[0].data[] |
    . as $m | ($cur[$m.id] // null) as $o |
    ($m.supported_reasoning_levels // [] | map(.effort) | map(select(. as $e | $valid_efforts | index($e)))) as $efforts |
    ($m.modalities.input // [] | map(select(. == "text" or . == "image"))) as $input |
    (($m.display_name // "") as $dn | if $dn != "" and $dn != $m.id then $dn else "" end) as $name |
    (($m.context_length // $m.context_window // $m.max_input_tokens) as $c | if ($c | type) == "number" and $c > 0 then $c else null end) as $ctx |
    (($m.max_output_tokens) as $x | if ($x | type) == "number" and $x > 0 then $x else null end) as $out |
    # 差集条件：仅用于补充 omp 缺失或不全的能力，绝不降级 omp 已知能力
    select(
      ($name != "" and ($o == null or $o.name == $o.id)) or
      ($ctx != null and ($o == null or $o.contextWindow != $ctx)) or
      ($out != null and ($o == null or $o.maxTokens != $out)) or
      ($efforts | length > 0 and ($o == null or ($efforts != ($o.thinking // [])))) or
      (($m.reasoning == true or ($efforts | length > 0)) and ($o == null or ($o.reasoning // false) != true)) or
      (($input | length > 0) and ($o == null or (($input | sort) != ($o.input // [] | sort))))
    ) |
    "      \($m.id):\n" +
    (if $name != "" then
      "        name: \($name | tojson)\n"
     else "" end) +
    (if $ctx != null and ($o == null or $o.contextWindow != $ctx) then
      "        contextWindow: \($ctx)\n"
     else "" end) +
    (if $out != null and ($o == null or $o.maxTokens != $out) then
      "        maxTokens: \($out)\n"
     else "" end) +
    (if ($m.reasoning == true or ($efforts | length > 0)) then
      "        reasoning: true\n"
     else "" end) +
    (if ($input | length > 0) and ($o == null or (($input | sort) != ($o.input // [] | sort))) then
      "        input: [" + ($input | map("\"" + . + "\"") | join(", ")) + "]\n"
     else "" end) +
    (if ($efforts | length > 0) and ($o == null or ($efforts != ($o.thinking // []))) then
      "        thinking:\n          mode: effort\n          efforts: [" + ($efforts | join(", ")) + "]\n" +
      "        compat:\n          supportsReasoningEffort: true\n          omitReasoningEffort: false\n"
     else "" end)
  ] | join("")')

if [ -n "$OVERRIDES" ]; then
  cat << EOF > "$BLOCK_FILE"
    modelOverrides:
$OVERRIDES
EOF
else
  : > "$BLOCK_FILE"
fi

# 5. 确保 models.yml 中存在锚点注释，存在则替换区域内容
if ! grep -q '# >>> mp-modelOverrides:auto-sync >>>' "$MODELS_FILE"; then
  awk '
    /^  mp:/ { in_mp = 1 }
    in_mp && /timeoutMs:/ {
      print
      print "    # >>> mp-modelOverrides:auto-sync >>>"
      print "    # <<< mp-modelOverrides:auto-sync <<<"
      in_mp = 0
      next
    }
    { print }
  ' "$MODELS_FILE" > "${MODELS_FILE}.tmp" && mv "${MODELS_FILE}.tmp" "$MODELS_FILE"
fi

# 使用 awk 替换锚点区间
awk -v block_file="$BLOCK_FILE" '
  BEGIN { in_block = 0 }
  /# >>> mp-modelOverrides:auto-sync >>>/ {
    print $0
    while ((getline line < block_file) > 0) print line
    in_block = 1
    next
  }
  /# <<< mp-modelOverrides:auto-sync <<</ {
    in_block = 0
    print $0
    next
  }
  !in_block { print }
' "$MODELS_FILE" > "${MODELS_FILE}.tmp" && mv "${MODELS_FILE}.tmp" "$MODELS_FILE"

echo "mp modelOverrides 同步完成 -> ${MODELS_FILE}"
