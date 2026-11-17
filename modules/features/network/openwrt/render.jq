# 输入：未展开的 uci.json；参数 $secrets：sops -d 解出的 JSON（--slurpfile 得到的数组）。输出：展开后的 uci.json。
# 声明里写 "{{ sops.<路径> }}" 的字符串整串替换成 sops 里对应路径的值，如 "{{ sops.wifi.main.ssid }}" 取 .wifi.main.ssid。
# 路径在 sops 里不存在、不是字符串或是空字符串时报错退出。展开后再扫一遍整个输出：还有任何 sops 占位符
# （写错格式的、夹在别的文字里的、sops 值里自带的）一律报错，不让占位符原样下发。报错信息不带值。
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
