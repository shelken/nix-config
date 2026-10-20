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
  [${glyph "E0BA"}](fg:white)\
  $os\
  [${glyph "E0BC"}](bg:blue fg:white)\
  $directory\
  [${glyph "E0BC"}](bg:green fg:blue)\
  $git_branch\
  $git_status\
  [${glyph "E0B0"}](fg:green)
  $character"""

  right_format = """
  [${glyph "E0B2"}](fg:black)\
  $status\
  $cmd_duration\
  $kubernetes\
  $terraform\
  $nix_shell\
  $hostname\
  [${glyph "E0BA"}](bg:black fg:white)\
  $time\
  [${glyph "E0BC"}](fg:white)"""

  [os]
  disabled = false
  style = 'bg:white fg:232'
  format = '[ $symbol ]($style)'
  [os.symbols]
  Macos = '🤘'

  [directory]
  style = 'bg:blue fg:254'
  format = '[ ${glyph "F07C"} $path ]($style)'
  truncation_length = 4
  truncation_symbol = '…/'
  truncate_to_repo = false
  use_os_path_sep = true

  [git_branch]
  style = 'bg:green fg:black'
  format = '[ ${glyph "F113"} ${glyph "F126"} $branch ]($style)'

  # 整段被 (...) 包住：干净时黄块和它的分隔符一起消失。
  [git_status]
  style = 'bg:yellow fg:black'
  format = '([${glyph "E0BC"}](bg:yellow fg:green)[ $all_status ]($style))'
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
  style = 'bg:red fg:yellow'
  format = '[ ✘$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:yellow fg:black'
  format = '[ ${glyph "F252"}$duration ]($style)'

  [kubernetes]
  disabled = false
  symbol = '${glyph "F10FE"} '
  style = 'bg:blue fg:white'
  format = '[ $symbol$context( \($namespace\)) ]($style)'

  [terraform]
  disabled = false
  symbol = '${glyph "F1BB"} '
  style = 'bg:black fg:white'
  format = '[ $symbol$workspace ]($style)'

  [nix_shell]
  disabled = false
  symbol = '${glyph "F313"} '
  style = 'bg:blue fg:black'
  format = '[ $symbol$state( \($name\)) ]($style)'

  # p10k 的 context 段：user@hostname，本机也常显
  [hostname]
  ssh_only = false
  style = 'bg:black fg:yellow'
  format = '[ @$hostname ]($style)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:white fg:black'
  format = '[ $time ${glyph "F017"} ]($style)'

  [character]
  success_symbol = '[❯](fg:76)'
  error_symbol = '[❯](fg:196)'
''
