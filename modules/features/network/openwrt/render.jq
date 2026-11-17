# 输入：未展开的 uci.json；参数 $secrets：sops -d 解出的 JSON（--slurpfile 得到的数组）。输出：展开后的 uci.json。
# 声明里写 "{{ sops.<路径> }}" 的字符串整串替换成 sops 里对应路径的值，如 "{{ sops.wifi.main.ssid }}" 取 .wifi.main.ssid。
# 路径在 sops 里不存在或不是字符串时报错退出；残留的 "{{ sops." 也报错，不让占位符原样下发。报错信息不带值
def expand:
  if test("^\\{\\{ sops\\.[^ ]+ \\}\\}$")
  then
    capture("^\\{\\{ sops\\.(?<path>[^ ]+) \\}\\}$").path as $path
    | ($secrets[0] | getpath($path | split("."))) as $v
    | if ($v | type) == "string" then $v else error("sops 里没有字符串值：\($path)") end
  elif contains("{{ sops.")
  then error("占位符格式不对：整个值必须是 {{ sops.<路径> }}")
  else .
  end;

walk(if type == "string" then expand else . end)
