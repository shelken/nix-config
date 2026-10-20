# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取，不是文档推断）：
#   左：E0BA(白) → 🤘(白底/232) → E0BC → 目录(蓝底/254) → E0BC → git(绿底/30) → E0B0(绿)
#   右：E0B2(黑) → @mio(黑底/33) → E0BA(黑底/白) → 时间+F017(白底/30) → E0BC(白)
#
# 颜色：背景 ANSI 0-7，前景 xterm256 索引。不依赖 truecolor。
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
  [${glyph "E0BC"}](bg:#a6da95 fg:#8aadf4)\
  $git_branch\
  $git_status\
  [${glyph "E0B0"}](fg:#a6da95)
  $character"""

  right_format = """
  [${glyph "E0B2"}](fg:#494d64)\
  $status\
  $cmd_duration\
  $kubernetes\
  $terraform\
  $hostname\
  $nix_shell\
  [${glyph "E0BA"}](bg:#494d64 fg:#b8c0e0)\
  $time\
  [${glyph "E0BC"}](fg:#b8c0e0)"""

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

  [git_branch]
  style = 'bg:#a6da95 fg:#494d64'
  format = '[ ${glyph "F113"} ${glyph "F126"} $branch ]($style)'

  # 整段被 (...) 包住：干净时黄块和它的分隔符一起消失。
  [git_status]
  style = 'bg:#eed49f fg:#494d64'
  format = '([${glyph "E0BC"}](bg:#eed49f fg:#a6da95)[ $all_status ]($style))'
  conflicted = '~'
  ahead = '⇡'
  behind = '⇣'
  diverged = '⇕'
  untracked = '?'
  stashed = '*'
  modified = '!'
  staged = '+'
  renamed = '»'
  deleted = '✘'

  [status]
  disabled = false
  style = 'bg:#ed8796 fg:#eed49f'
  format = '[ ✘$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:#eed49f fg:#494d64'
  format = '[ ${glyph "F252"}$duration ]($style)'

  [kubernetes]
  disabled = false
  symbol = '${glyph "F10FE"} '
  style = 'bg:#8aadf4 fg:#b8c0e0'
  format = '[ $symbol$context( \($namespace\)) ]($style)'

  [terraform]
  disabled = false
  symbol = '${glyph "F1BB"} '
  style = 'bg:#494d64 fg:#b8c0e0'
  format = '[ $symbol$workspace ]($style)'

  [nix_shell]
  disabled = false
  symbol = '${glyph "F313"} '
  style = 'bg:#8aadf4 fg:#494d64'
  format = '[ $symbol$state ]($style)'

  # p10k 的 context 段：user@hostname，本机也常显
  [hostname]
  ssh_only = false
  style = 'bg:#494d64 fg:#eed49f'
  format = '[ @$hostname ]($style)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:#b8c0e0 fg:#494d64'
  format = '[ $time ${glyph "F017"} ]($style)'

  [character]
  success_symbol = '[❯](fg:76)'
  error_symbol = '[❯](fg:196)'
''
