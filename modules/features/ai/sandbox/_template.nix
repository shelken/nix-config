# 求值期把脚本里的 @名字@ 占位符替换成值，返回替换后的文本。
# 不用 replaceVars + readFile：后者读取依赖 Linux guest 脚本的派生产物，
# 导致求值宿主配置也要先构建 Linux 包（IFD）。
# 与裸 replaceStrings 的区别：占位符在脚本里不存在、或脚本里还有没人替换的 @名字@，都在求值时报错，
# 不会静默漏替换。
{ lib }:
file: vars:
let
  text = builtins.readFile file;
  names = builtins.attrNames vars;
  marks = map (n: "@${n}@") names;
  unused = builtins.filter (n: !(lib.hasInfix "@${n}@" text)) names;
  # 只在模板自身的文字里找残留：先把已知占位符抹掉，注入的值（可能含 @）不参与检查
  leftover = lib.concatMap (m: if builtins.isList m then m else [ ]) (
    builtins.split "(@[A-Za-z_]+@)" (builtins.replaceStrings marks (map (_: "") marks) text)
  );
in
assert lib.assertMsg (unused == [ ]) "${toString file}: 脚本里没有这些占位符：${toString unused}";
assert lib.assertMsg (leftover == [ ]) "${toString file}: 脚本里有没人替换的占位符：${toString leftover}";
builtins.replaceStrings marks (map (n: "${vars.${n}}") names) text
