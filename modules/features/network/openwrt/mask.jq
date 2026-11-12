# 输入：未展开的 uci.json；参数 $esc：ESC 字符。输出：sed 打码规则。
# 声明里写了 {{ op://… }} 的每个选项，对应 nuci diff 输出里的一个键：
# nuci 把匿名段显示成 @类型[序号]，列表值拼成一行，所以路径里的段序号要转换、列表项序号要丢掉。
def key:
  .[1:] as $q
  | if ($q[2] | type) == "number"
    then "\($q[0]).@\($q[1])[\($q[2])].\($q[3])"
    else "\($q[0]).\($q[1]).\($q[2])"
    end;

[
  paths(type == "string" and test("\\{\\{ op://"))
  | select(.[0] == "settings")
  | key
  | gsub("(?<c>[.\\[\\]])"; "\\\(.c)")
  | "s/(\(.)=)[^\($esc)]*/\\1<masked>/"
] | join(";")
