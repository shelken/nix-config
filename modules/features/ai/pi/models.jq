# 把 omp/models.yml 与 pi/models.yml（均已转成 JSON）合成 pi 的 models.json。
# 用法: jq -S -s -f models.jq omp-models.json pi-models.json
# 输入是 [omp, pi] 两个文档；pi 的同名字段覆盖 omp，对象递归合并，数组整体替换。

# omp thinking -> pi thinkingLevelMap 键位对齐 (pi 1.3.0 wire 序列化):
#   reasoning ? effortMap[reasoning] ?? "high" : effortMap.off ?? void 0
# - omp efforts[i]         -> pi <level> (compat.reasoningEffortMap 可改写档位;
#     pi 会忽略该 compat 字段, 必须折进 map)
# - omp defaultLevel       -> 不映射: pi 缺档时已回落 "high"
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
        # 供应商级 compat 与模型级 compat 浅合并，模型级优先，再折进 thinkingLevelMap
        (if $provider | has("compat") then .compat = (($provider.compat // {}) + (.compat // {})) else . end)
        | adaptModel
      )
    else . end;

(.[0] * .[1]) | {providers: (.providers | map_values(adaptProvider))}
