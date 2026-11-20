# 用 \A \z 而不是 ^ $：后者在这个正则引擎里按行匹配，多行字符串会被当成整个值替换掉。
def expand:
  if test("\\A\\{\\{ sops\\.[^\\s]+ \\}\\}\\z")
  then
    capture("\\A\\{\\{ sops\\.(?<path>[^\\s]+) \\}\\}\\z").path as $path
    | (try ($secrets[0] | getpath($path | split("."))) catch null) as $v
    | if ($v | type) == "string" and $v != "" then $v else error("sops 里没有非空字符串值：\($path)") end
  else .
  end;

def leftover: [.. | (strings, (objects | keys[]))] | map(select(test("\\{\\{\\s*sops\\."; "i"))) | length;

walk(if type == "string" then expand else . end)
| if leftover > 0
  then error("输出里还有 \(leftover) 处 sops 占位符：整个值必须是 {{ sops.<路径> }}，且 sops 里的值不能再带占位符")
  else .
  end
