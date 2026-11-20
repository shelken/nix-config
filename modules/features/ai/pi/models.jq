# - omp efforts[i]         -> pi <level> (compat.reasoningEffortMap 可改写档位;
#     pi 会忽略该 compat 字段, 必须折进 map)
# - omp requiresEffort:true -> pi off: <最低档>。off 置 null 时 pi 关思考不
#     带 reasoning.effort, 强制思考模型 (cpa 全系) 400; 混合模型保持 null
def adaptModel:
  (.thinking // null) as $thinking
  | (if $thinking == null then [] else $thinking.efforts // [] end) as $efforts
  | (.compat.reasoningEffortMap // {}) as $effortMap
  | ($thinking != null and ($thinking.requiresEffort // false)) as $requiresEffort
  | del(.thinking)
  | if ($efforts | length) > 0 then
      .thinkingLevelMap = (
        {off: (if $requiresEffort then $efforts[0] else null end)}
        + ($efforts | map(. as $level | {key: $level, value: (if $effortMap | has($level) then $effortMap[$level] else $level end)}) | from_entries)
      )
    else . end;

def adaptProvider:
  . as $provider
  | del(.discovery)
  | if ($provider | has("apiKey")) and ($provider.apiKey | test("^[A-Z][A-Z0-9_]*$")) then
      .apiKey = "$" + $provider.apiKey
    else . end
  | if $provider | has("models") then .models |= map(adaptModel) else . end
  | if $provider | has("modelOverrides") then
      .modelOverrides |= map_values(
        (if $provider | has("compat") then .compat = (($provider.compat // {}) + (.compat // {})) else . end)
        | adaptModel
      )
    else . end;

(.[0] * .[1]) | {providers: (.providers | map_values(adaptProvider))}
