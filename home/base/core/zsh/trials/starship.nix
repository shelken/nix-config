# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 三色块 + slanted 分隔符 + 两行）。
#
# 与 p10k 的已知差异（Starship 能力边界，无法消除）：
#   - Zsh 没有 transient prompt；Instant Prompt 也没有。
#   - dir 无法把路径分隔符换成 ╱（子段分隔符）。
#   - 没有 show-on-command（kube/terraform/… 在相应环境一直显示）。
#   - git 变脏时 p10k 让整段变黄，这里只有 git_status 变黄（git_branch 仍为绿）。
#
# 导出：
#   nix eval --raw --impure --expr 'import ./home/base/core/zsh/trials/starship.nix' > /tmp/prompt-trial/starship.toml
let
  # Nix 不支持 \u 转义；用 JSON 解析得到字形，避免源码里出现不可见字符。
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  sep = glyph "E0BC"; # p10k LEFT_SEGMENT_SEPARATOR
  folder = glyph "F115"; # dir
  branch = glyph "F126"; # vcs branch
  clock = glyph "F252"; # command_execution_time
  kube = glyph "F10FE"; # kubecontext
  tf = glyph "F1BB"; # terraform
  aws = glyph "F270"; # aws
  azure = glyph "EBD8"; # azure
  gcloud = glyph "F02AD"; # gcloud
  nixIcon = glyph "F313"; # nix_shell
  timeIcon = glyph "F017"; # time
  fail = glyph "F00D"; # status error
in
''
  # p10k -> starship。ANSI 编号按 catppuccin macchiato 的 16 色映射；
  # 232/254/76/196 是 xterm256 固定值，catppuccin 不重映射。
  "$schema" = 'https://starship.rs/config-schema.json'
  palette = 'p10k'
  add_newline = true

  format = """
  [ 🤘 ](bg:subtext1 fg:black232)\
  [${sep}](bg:blue fg:subtext1)\
  $directory\
  [${sep}](bg:green fg:blue)\
  $git_branch\
  $git_status\
  $fill\
  $status\
  $cmd_duration\
  $kubernetes\
  $terraform\
  $aws\
  $azure\
  $gcloud\
  $nix_shell\
  $hostname\
  $time
  $character"""

  [directory]
  style = 'bg:blue fg:gray254'
  format = '[ ${folder}$path ]($style)'
  truncation_length = 0
  truncation_symbol = '…/'

  [git_branch]
  symbol = '${branch} '
  style = 'bg:green fg:surface1'
  format = '[ $symbol$branch ]($style)'

  [git_status]
  style = 'bg:yellow fg:surface1'
  format = '[${sep}](bg:yellow fg:green)[ $all_status$ahead_behind ]($style)'

  [status]
  disabled = false
  style = 'bg:red fg:yellow'
  format = '[ ${fail}$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:yellow fg:surface1'
  format = '[${sep}](bg:yellow fg:red)[ ${clock}$duration ]($style)'

  [kubernetes]
  disabled = false
  symbol = '${kube} '
  style = 'bg:mauve fg:subtext1'
  format = '[${sep}](bg:mauve fg:yellow)[ $symbol$context( \($namespace\)) ]($style)'

  [terraform]
  disabled = false
  symbol = '${tf} '
  style = 'bg:surface1 fg:subtext1'
  format = '[${sep}](bg:surface1 fg:mauve)[ $symbol$workspace ]($style)'

  [aws]
  disabled = false
  symbol = '${aws} '
  style = 'bg:red fg:subtext1'
  format = '[${sep}](bg:red fg:surface1)[ $symbol$profile( \($region\)) ]($style)'

  [azure]
  disabled = false
  symbol = '${azure} '
  style = 'bg:blue fg:subtext1'
  format = '[${sep}](bg:blue fg:red)[ $symbol$subscription ]($style)'

  [gcloud]
  disabled = false
  symbol = '${gcloud} '
  style = 'bg:blue fg:subtext1'
  format = '[${sep}](bg:blue fg:blue)[ $symbol$project ]($style)'

  [nix_shell]
  disabled = false
  symbol = '${nixIcon} '
  style = 'bg:blue fg:surface1'
  format = '[${sep}](bg:blue fg:blue)[ $symbol$state( \($name\)) ]($style)'

  [hostname]
  ssh_only = true
  style = 'bg:surface1 fg:yellow'
  format = '[${sep}](bg:surface1 fg:blue)[ @$hostname ]($style)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:subtext1 fg:surface1'
  format = '[${sep}](bg:subtext1 fg:surface1)[ ${timeIcon}$time ]($style)'

  [character]
  success_symbol = '[❯](fg:green76)'
  error_symbol = '[❯](fg:red196)'

  [palettes.p10k]
  black232 = '#080808'
  gray254 = '#e4e4e4'
  green76 = '#5fd700'
  red196 = '#ff0000'
  surface1 = '#494d64'
  red = '#ed8796'
  green = '#a6da95'
  yellow = '#eed49f'
  blue = '#8aadf4'
  mauve = '#c6a0f6'
  subtext1 = '#b8c0e0'
''
