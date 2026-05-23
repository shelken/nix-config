# cpa-warm - 并发发送 CPA warm 请求
# Usage:
#   cpa-warm [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>] [--input <text>]
#   cpa-warm --help | -h

emulate -L zsh
unsetopt monitor notify

local apiurl="http://127.0.0.1:8317"
local model="gpt-5.4-mini(none)"
local envkey="PI_CPA_API_KEY"
local max=1
local base_input=""
local endpoint=""

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
    --input)
        if [[ -z "$2" ]]; then
            echo "Error: --input 缺少参数"
            return 1
        fi
        base_input="$2"
        shift 2
        ;;
    --help | -h)
        echo "Usage:"
        echo "  cpa-warm [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>] [--input <text>]"
        echo ""
        echo "默认值:"
        echo "  --apiurl http://127.0.0.1:8317"
        echo "  --model  gpt-5.4-mini(off)"
        echo "  --envkey PI_CPA_API_KEY"
        echo "  --max    1"
        echo ""
        echo "说明:"
        echo "  - 总请求数由 --max 控制"
        echo "  - 固定按 3 并发分批发送"
        echo "  - 不传 --input 时，每次自动生成 echo <random_int>"
        echo "  - 传 --input 时，每次会在末尾追加 random_int，保证每次 input 不同"
        echo "  - 终端默认只显示参数摘要和成功/失败统计"
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

local input_preview=""
if [[ -n "$base_input" ]]; then
    input_preview="${base_input} <random_int>"
else
    input_preview="echo <random_int>"
fi

echo "运行参数:"
echo "  apiurl: $apiurl"
echo "  model: $model"
echo "  envkey: $envkey"
echo "  max: $max"
echo "  input: $input_preview"

local tmp_dir
if ! tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/cpa-warm.XXXXXX"); then
    echo "Error: 无法创建临时目录"
    return 1
fi

local failed=0
local success_count=0
local failure_count=0
local index=1

while ((index <= max)); do
    local -a pids=()
    local -a err_files=()
    local -a inputs=()

    while ((${#pids} < 3 && index <= max)); do
        local random_int="${RANDOM}${RANDOM}${index}"
        local request_input=""
        local err_file="${tmp_dir}/response-${index}.err"

        if [[ -n "$base_input" ]]; then
            request_input="${base_input} ${random_int}"
        else
            request_input="echo ${random_int}"
        fi

        (
            local body
            body=$(jq -nc --arg model "$model" --arg input "$request_input" '{ model: $model, input: $input }') || exit 1
            command curl -fsS "$endpoint" \
                -H "Authorization: Bearer $api_key" \
                -H "Content-Type: application/json" \
                -d "$body"
        ) >/dev/null 2>"$err_file" &

        pids+=("$!")
        err_files+=("$err_file")
        inputs+=("$request_input")
        ((index++))
    done

    local i=0
    for ((i = 1; i <= ${#pids}; i++)); do
        if wait "${pids[$i]}"; then
            ((success_count++))
            continue
        fi

        failed=1
        ((failure_count++))
        echo "请求失败: ${inputs[$i]}" >&2
        local err_text="$(<"${err_files[$i]}")"
        if [[ -n "$err_text" ]]; then
            echo "$err_text" >&2
        fi
    done
done

echo "成功: $success_count 失败: $failure_count"

rm -rf "$tmp_dir"
return $failed
