# cpa-eval - 用糖果题测试 CPA 模型回答能力
# Usage:
#   cpa-eval [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>]
#   cpa-eval --help | -h

emulate -L zsh
zmodload zsh/datetime || return 1

local apiurl="http://127.0.0.1:8317"
local model="gpt-5.4-mini(none)"
local envkey="PI_CPA_API_KEY"
local max=1
local endpoint=""

local prompt='不使用任何外部工具回答以下问题：

在一个黑色的袋子里放有三种口味的糖果，每种糖果有两种不同的形状（圆形和五角星形，不同的形状靠手感可以分辨）。现已知不同口味的糖和不同形状的数量统计如下表。参赛者需要在活动前决定摸出的糖果数目，那么，最少取出多少个糖果才能保证手中同时拥有不同形状的苹果味和桃子味的糖？（同时手中有圆形苹果味匹配五角星桃子味糖果，或者有圆形桃子味匹配五角星苹果味糖果都满足要求）

        苹果味  桃子味  西瓜味
圆形       7      9      8
五角星形   7      6      4
'

while [[ $# -gt 0 ]]; do
    case "$1" in
    --apiurl)
        if [[ -z "$2" ]]; then
            echo "Error: --apiurl 缺少参数"
            return 1
        fi
        apiurl="$2"
        shift 2
        ;;
    --model)
        if [[ -z "$2" ]]; then
            echo "Error: --model 缺少参数"
            return 1
        fi
        model="$2"
        shift 2
        ;;
    --envkey)
        if [[ -z "$2" ]]; then
            echo "Error: --envkey 缺少参数"
            return 1
        fi
        envkey="$2"
        shift 2
        ;;
    --max)
        if [[ -z "$2" ]]; then
            echo "Error: --max 缺少参数"
            return 1
        fi
        max="$2"
        shift 2
        ;;
    --help | -h)
        echo "Usage:"
        echo "  cpa-eval [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>]"
        echo ""
        echo "默认值:"
        echo "  --apiurl http://127.0.0.1:8317"
        echo "  --model  gpt-5.4-mini(none)"
        echo "  --envkey PI_CPA_API_KEY"
        echo "  --max    1"
        echo ""
        echo "说明:"
        echo "  - 直接请求 <apiurl>/v1/chat/completions，不调用 cpa 命令"
        echo "  - 使用 codex-candy-eval 的糖果题，回答中出现独立的 21 判为正确"
        echo "  - --max 控制测试次数"
        return 0
        ;;
    *)
        echo "Error: 未知参数: $1"
        return 1
        ;;
    esac
done

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' not found."
    return 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' not found."
    return 1
fi

if [[ ! "$max" == <-> ]] || ((max < 1)); then
    echo "Error: --max 必须是大于等于 1 的整数"
    return 1
fi

local api_key="${(P)envkey}"
if [[ -z "$api_key" ]]; then
    echo "Error: 环境变量 $envkey 为空或未设置"
    return 1
fi

endpoint="${apiurl%/}/v1/chat/completions"

printf '运行参数:\n  apiurl: %s\n  model: %s\n  envkey: %s\n  max: %s\n\n' "$apiurl" "$model" "$envkey" "$max"
printf '%4s  %-40s  %8s  %8s  %10s  %7s  %3s\n' Run Answer InTok OutTok ReasonTok Time OK
printf '%4s  %-40s  %8s  %8s  %10s  %7s  %3s\n' ---- ---------------------------------------- -------- -------- ---------- ------- ---

local correct=0
local graded=0
local failed=0
local index=1

while ((index <= max)); do
    local body response elapsed start_time end_time text preview ok input_tok output_tok reason_tok

    body=$(jq -nc --arg model "$model" --arg input "$prompt" '{ model: $model, input: $input }') || return 1
    start_time="$EPOCHREALTIME"
    response=$(command curl -fsS "$endpoint" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$body" 2>&1)
    local curl_status=$?
    end_time="$EPOCHREALTIME"
    elapsed=$(awk -v start="$start_time" -v end="$end_time" 'BEGIN { printf "%.1f", end - start }')

    if ((curl_status != 0)); then
        failed=1
        printf '%4s  %-40s  %8s  %8s  %10s  %7s  %3s\n' "$index" "ERROR: ${response[1,33]}" - - - "$elapsed" -
        ((index++))
        continue
    fi

    text=$(jq -r '
        [
          .output_text?,
          .choices[0].message.content?,
          .choices[0].text?,
          ([.. | objects | select((.type? == "output_text") or (.type? == "text")) | .text?] | join("\n"))
        ]
        | map(select(type == "string" and length > 0))
        | first // ""
    ' <<<"$response") || return 1
    input_tok=$(jq -r '.usage.input_tokens // .usage.prompt_tokens // "-"' <<<"$response") || return 1
    output_tok=$(jq -r '.usage.output_tokens // .usage.completion_tokens // "-"' <<<"$response") || return 1
    reason_tok=$(jq -r '.usage.reasoning_output_tokens // .usage.output_tokens_details.reasoning_tokens // .usage.completion_tokens_details.reasoning_tokens // "-"' <<<"$response") || return 1

    preview="${text//$'\n'/\\n}"
    if (( ${#preview} > 40 )); then
        preview="${preview[1,37]}..."
    fi

    if [[ "$text" =~ (^|[^0-9])21([^0-9]|$) ]]; then
        ok="✓"
        ((correct++))
    else
        ok="✗"
    fi
    ((graded++))

    printf '%4s  %-40s  %8s  %8s  %10s  %7s  %3s\n' "$index" "$preview" "$input_tok" "$output_tok" "$reason_tok" "$elapsed" "$ok"
    ((index++))
done

if ((graded > 0)); then
    local accuracy
    accuracy=$(awk -v c="$correct" -v g="$graded" 'BEGIN { printf "%.1f", c / g * 100 }')
    printf '\nGraded %s/%s  correct=%s  accuracy=%s%%\n' "$graded" "$max" "$correct" "$accuracy"
else
    printf '\nGraded 0/%s\n' "$max"
fi

return $failed
