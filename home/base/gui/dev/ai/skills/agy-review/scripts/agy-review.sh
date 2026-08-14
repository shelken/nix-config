#!/usr/bin/env bash
# agy-review.sh — adversarial critique of anything via the `agy` (Antigravity) CLI.
#
# Pipes whatever you give it — a plan, design, code, writing, decision, argument,
# config, or idea — into `agy` in non-interactive print mode and prints back a
# red-team critique: assumptions, flaws, risks, gaps, and a SHIP/REVISE/RETHINK
# verdict. Default model: Gemini 3.5 Flash in its highest thinking mode.
#
# Usage:
#   agy-review.sh -f FILE                    # review a file
#   agy-review.sh "<text to review>"         # review an inline string
#   echo "<text>" | agy-review.sh -          # read the content from stdin
#   agy-review.sh -f design.md -c "context"  # add context about what it is / goals
#
# Options:
#   -f, --file FILE     read the content to review from FILE
#   -c, --context STR   what it is / goals / constraints, to focus the review
#   -m, --model NAME    model (default $AGY_REVIEW_MODEL or "Gemini 3.5 Flash (High)"; see `agy models`)
#   -h, --help          show this help
#
# Env: AGY_REVIEW_MODEL · AGY_PRINT_TIMEOUT (2m) · AGY_HARD_TIMEOUT (150s)
# Exit: 0 critique printed · 1 usage error · 2 agy missing or returned nothing
set -euo pipefail

MODEL="${AGY_REVIEW_MODEL:-Gemini 3.5 Flash (High)}"
PRINT_TIMEOUT="${AGY_PRINT_TIMEOUT:-2m}"
HARD_TIMEOUT="${AGY_HARD_TIMEOUT:-150}"
INPUT=""; CONTEXT=""

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--file)    [ -r "${2:-}" ] || { echo "error: cannot read file '${2:-}'" >&2; exit 1; }; INPUT="$(cat "$2")"; shift 2 ;;
    -c|--context) CONTEXT="${2:-}"; shift 2 ;;
    -m|--model)   MODEL="${2:-}"; shift 2 ;;
    -h|--help)    usage 0 ;;
    -)            INPUT="$(cat -)"; shift ;;
    -*)           echo "error: unknown option '$1'" >&2; usage 1 ;;
    *)            INPUT="$1"; shift ;;
  esac
done
if [ -z "$INPUT" ] && [ ! -t 0 ]; then INPUT="$(cat -)"; fi
[ -n "$INPUT" ] || { echo "error: no input provided (use -f FILE, an argument, or stdin)" >&2; usage 1; }
command -v agy >/dev/null 2>&1 || { echo "error: 'agy' CLI not found on PATH" >&2; exit 2; }

CTX=""
[ -n "$CONTEXT" ] && CTX="

Context (what this is / goals / constraints): ${CONTEXT}"

PROMPT="Adversarially critique the content below. Find its biggest problems: questionable assumptions, weaknesses, flaws, risks, gaps, and ways it could fail, be wrong, or be a bad idea. Be specific and skeptical; do not restate or praise it; just give the critique as concise bullets. End with one line: VERDICT: SHIP / REVISE / RETHINK - <the single biggest issue>.

Content to critique:
${INPUT}${CTX}"

# IMPORTANT: agy's -p / --print / --prompt takes the prompt as its VALUE, so every
# other flag (--model, --print-timeout) MUST come before it, with -p "$PROMPT" last.
# (Putting -p first makes it swallow the next flag as the prompt — a silent failure.)
# Run from a throwaway empty dir so agy never treats your project as a workspace.
d="$(mktemp -d)"
OUT="$( cd "$d" && timeout -k 5s "$HARD_TIMEOUT" agy --model "$MODEL" --print-timeout "$PRINT_TIMEOUT" -p "$PROMPT" 2>&1 )" || true
rm -rf "$d" 2>/dev/null || true

if [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then
  echo "error: agy returned no output (model='$MODEL'). Check 'agy --version', 'agy models', and your network." >&2
  exit 2
fi
printf '%s\n' "$OUT"
