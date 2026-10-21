# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取，不是文档推断）：
#   第 1 行 左：E0BA(白) → 🤘(白底/232) → E0BC → 目录(蓝底/254) → E0BC → git → E0B0(跟随 git 底色)
#   第 1 行 右：E0B2 → [direnv ▼ ╱] @mio(黑底/黄) → [nix_shell(蓝底)] → 时间+F017(白底) → E0BC
#   第 2 行：❯
#
# 颜色写死 Catppuccin Macchiato hex（Catppuccin 官方 starship 预设同样用 hex palette）；
# 前景 232/254/76/196 是 xterm256 索引，主题不会重映射。
#
# Starship 的 right_format 在 zsh 里落在最后一行，所以右侧用 $fill 放进第 1 行。
# 收尾箭头的颜色取决于 git 是否变脏，没有单模块能表达，用两个 custom 模块（when 条件）补。
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";
in
''
  "$schema" = 'https://starship.rs/config-schema.json'
  add_newline = true

  format = """
  [${glyph "E0BA"}](fg:#b8c0e0)\
  $os\
  [${glyph "E0BC"}](bg:#8aadf4 fg:#b8c0e0)\
  $directory\
  $git_branch\
  $git_status\
  ''${custom.end_nogit}\
  ''${custom.end_clean}\
  $fill\
  [${glyph "E0B2"}](fg:#494d64)\
  $status\
  $cmd_duration\
  $direnv\
  $hostname\
  $nix_shell\
  ''${custom.time_cap}\
  $time\
  [${glyph "E0BC"}](fg:#b8c0e0)
  $character"""

  [fill]
  symbol = ' '

  [os]
  disabled = false
  style = 'bg:#b8c0e0 fg:232'
  format = '[ $symbol ]($style)'
  [os.symbols]
  Macos = '🤘'

  [directory]
  style = 'bg:#8aadf4 fg:254'
  format = '[ ${glyph "F07C"} $path ]($style)'
  truncation_length = 4
  truncation_symbol = '…/'
  truncate_to_repo = false
  use_os_path_sep = true

  # 分隔符放进 git 模块：不在仓库里时不会冒出孤立的绿色箭头。
  [git_branch]
  style = 'bg:#a6da95 fg:#494d64'
  format = '[${glyph "E0BC"}](bg:#a6da95 fg:#8aadf4)[ ${glyph "F113"} ${glyph "F126"} $branch ]($style)'

  # 整段被 (...) 包住：干净时黄块、分隔符、收尾箭头一起消失。
  [git_status]
  style = 'bg:#eed49f fg:#494d64'
  format = '([${glyph "E0BC"}](bg:#eed49f fg:#a6da95)[ $all_status]($style)[${glyph "E0B0"}](fg:#eed49f))'
  conflicted = '~''${count} '
  stashed = ""
  deleted = '✘''${count} '
  renamed = '»''${count} '
  modified = '!''${count} '
  staged = '+''${count} '
  untracked = '?''${count} '

  # 不在 git 仓库：目录段收尾（蓝色箭头）。
  [custom.end_nogit]
  when = '! git rev-parse --git-dir >/dev/null 2>&1'
  format = '[${glyph "E0B0"}](fg:#8aadf4)'

  # 在仓库且干净：绿色收尾箭头。判定与 git_status 的 $all_status 一致（含未跟踪）。
  [custom.end_clean]
  when = 'git rev-parse --git-dir >/dev/null 2>&1 && test -z "$(git status --porcelain 2>/dev/null)"'
  format = '[${glyph "E0B0"}](fg:#a6da95)'

  [status]
  disabled = false
  style = 'bg:#ed8796 fg:#eed49f'
  format = '[ ✘$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:#eed49f fg:#494d64'
  format = '[ ${glyph "F252"}$duration ]($style)'

  [direnv]
  disabled = false
  style = 'bg:#494d64 fg:#eed49f'
  format = '[ ▼ ╱]($style)'

  # p10k 的 context 段：@主机名，本机也常显
  [hostname]
  ssh_only = false
  style = 'bg:#494d64 fg:#eed49f'
  format = '[ @$hostname ]($style)'

  # 在 nix shell 里：黑 → 蓝 → 白；不在：黑 → 白（由 time_cap 补）。
  [nix_shell]
  disabled = false
  impure_msg = 'impure'
  pure_msg = 'pure'
  unknown_msg = 'nix'
  style = 'bg:#8aadf4 fg:#494d64'
  format = '[${glyph "E0BA"}](bg:#494d64 fg:#8aadf4)[ $state ${glyph "F313"} ]($style)[${glyph "E0BA"}](bg:#8aadf4 fg:#b8c0e0)'

  [custom.time_cap]
  when = 'test -z "$IN_NIX_SHELL"'
  format = '[${glyph "E0BA"}](bg:#494d64 fg:#b8c0e0)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:#b8c0e0 fg:#494d64'
  format = '[ $time ${glyph "F017"} ]($style)'

  [character]
  success_symbol = '[❯](fg:76)'
  error_symbol = '[❯](fg:196)'
''
