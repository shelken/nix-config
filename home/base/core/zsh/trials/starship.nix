# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 色块 + slanted 分隔符 + 两行）。
#
# 颜色直接取 p10k 的运行时值：
#   背景用 ANSI 0-7（跟随终端调色板），前景用 xterm256 索引（232/254/0/76/196）。
# 256 色是标准调色板，kitty 和 herdrm 显示完全一致，不依赖 truecolor。
#
# 导出：
#   nix eval --raw --impure --expr 'import ./home/base/core/zsh/trials/starship.nix'
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  # 字形取自 p10k 在本机的实际渲染输出，不是猜的。
  startCap = glyph "E0BA"; # LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  sep = glyph "E0BC"; # LEFT_SEGMENT_SEPARATOR
  end = glyph "E0B0"; # 左块末尾的实心箭头
  osIcon = glyph "F179"; # macOS
  folder = glyph "F07C"; # HOME_ICON
  gitIcon = glyph "F113"; # VCS_GIT_GITHUB_ICON
  branchIcon = glyph "F126"; # VCS_BRANCH_ICON
  clock = glyph "F252"; # EXECUTION_TIME_ICON
  timeIcon = glyph "F017"; # TIME_ICON
  kube = glyph "F10FE"; # KUBERNETES_ICON
  tf = glyph "F1BB"; # TERRAFORM_ICON
  awsIcon = glyph "F270"; # AWS_ICON
  azureIcon = glyph "EBD8"; # AZURE_ICON
  gcloudIcon = glyph "F02AD"; # GCLOUD_ICON
  nixIcon = glyph "F313"; # NIX_SHELL_ICON
  fail = glyph "F00D"; # FAIL_ICON

  # p10k 的实际配色（渲染核对过，不是估的）。
  osBg = "white"; # POWERLEVEL9K_OS_ICON
  osFg = "232";
  dirBg = "blue";
  dirFg = "254";
  gitBg = "green"; # 干净时
  gitFg = "0";
  dirtyBg = "yellow"; # 有改动时整段变黄
  errBg = "red"; # STATUS_ERROR_SIGNAL_BACKGROUND
  errFg = "3"; # STATUS_ERROR_SIGNAL_FOREGROUND
  chipFg = "7";
  timeBg = "white";
  timeFg = "0";
in
''
  "$schema" = 'https://starship.rs/config-schema.json'
  add_newline = true

  format = """
  [${startCap}](fg:${osBg})\
  $os\
  [${sep}](bg:${dirBg} fg:${osBg})\
  $directory\
  [${sep}](bg:${gitBg} fg:${dirBg})\
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

  [os]
  disabled = false
  style = 'bg:${osBg} fg:${osFg}'
  format = '[ $symbol ]($style)'
  [os.symbols]
  Macos = '${osIcon}'

  [directory]
  style = 'bg:${dirBg} fg:${dirFg}'
  format = '[ ${folder} $path ]($style)'
  truncation_length = 4
  truncation_symbol = '…/'
  truncate_to_repo = false
  use_os_path_sep = true

  [git_branch]
  symbol = '${gitIcon} ${branchIcon} '
  style = 'bg:${gitBg} fg:${gitFg}'
  format = '[ $symbol$branch ]($style)'

  # 整段被 (...) 包住：干净时黄块和它的分隔符一起消失。
  [git_status]
  style = 'bg:${dirtyBg} fg:${gitFg}'
  format = '([${sep}](bg:${dirtyBg} fg:${gitBg})[ $all_status$ahead_behind ]($style))'

  [status]
  disabled = false
  style = 'bg:${errBg} fg:${errFg}'
  format = '[ ${fail}$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:${dirtyBg} fg:${gitFg}'
  format = '[ ${clock}$duration ]($style)'

  [kubernetes]
  disabled = false
  symbol = '${kube} '
  style = 'bg:${dirBg} fg:${chipFg}'
  format = '[ $symbol$context( \($namespace\)) ]($style)'

  [terraform]
  disabled = false
  symbol = '${tf} '
  style = 'bg:black fg:${chipFg}'
  format = '[ $symbol$workspace ]($style)'

  # p10k 用 SHOW_ON_COMMAND 让这几段只在跑过对应命令后出现，Starship 没有这个能力：
  # 常驻显示会一直占位，默认关掉。
  [aws]
  disabled = true
  symbol = '${awsIcon} '
  style = 'bg:red fg:${chipFg}'
  format = '[ $symbol$profile( \($region\)) ]($style)'

  [azure]
  disabled = true
  symbol = '${azureIcon} '
  style = 'bg:${dirBg} fg:${chipFg}'
  format = '[ $symbol$subscription ]($style)'

  [gcloud]
  disabled = true
  symbol = '${gcloudIcon} '
  style = 'bg:${dirBg} fg:${chipFg}'
  format = '[ $symbol$project ]($style)'

  [nix_shell]
  disabled = false
  symbol = '${nixIcon} '
  style = 'bg:${dirBg} fg:${gitFg}'
  format = '[ $symbol$state( \($name\)) ]($style)'

  [hostname]
  ssh_only = true
  style = 'bg:black fg:${chipFg}'
  format = '[ @$hostname ]($style)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:${timeBg} fg:${timeFg}'
  format = '[ ${timeIcon}$time ]($style)'

  [fill]
  symbol = ' '

  [character]
  success_symbol = '[❯](fg:76)'
  error_symbol = '[❯](fg:196)'
''
