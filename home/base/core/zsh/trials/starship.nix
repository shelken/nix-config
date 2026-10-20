# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 三色块 + slanted 分隔符 + 两行）。
#
# 颜色用 ANSI 8 色名（不是 hex）：prompt 会跟随终端自身的调色板（kitty 的 catppuccin、
# herdrm 的调色板），不依赖 truecolor，也不需要在两个应用之间各调一次。
#
# 导出：
#   nix eval --raw --impure --expr 'import ./home/base/core/zsh/trials/starship.nix'
#   nix eval --raw --impure --expr 'import ./home/base/core/zsh/trials/starship.nix { palette = "warm"; }'
{ palette ? "classic" }:
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  # 字形取自 p10k 在本机的实际渲染输出，不是猜的。
  startCap = glyph "E0BA"; # LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  sep = glyph "E0BC"; # LEFT_SEGMENT_SEPARATOR
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

  palettes = {
    # p10k 现在的配色（蓝 → 绿）。
    classic = {
      osBg = "white";
      osFg = "black";
      dirBg = "blue";
      dirFg = "white";
      gitBg = "green";
      gitFg = "black";
      dirtyBg = "yellow";
      errBg = "red";
      errFg = "white";
      chipFg = "white";
      timeBg = "white";
      timeFg = "black";
    };
    # 青绿系：目录蓝、git 青，改动黄。比 classic 低一档饱和度。
    cool = {
      osBg = "white";
      osFg = "black";
      dirBg = "blue";
      dirFg = "white";
      gitBg = "cyan";
      gitFg = "black";
      dirtyBg = "yellow";
      errBg = "red";
      errFg = "white";
      chipFg = "white";
      timeBg = "white";
      timeFg = "black";
    };
    # 暖色：目录品红、git 青。
    warm = {
      osBg = "white";
      osFg = "black";
      dirBg = "purple";
      dirFg = "white";
      gitBg = "cyan";
      gitFg = "black";
      dirtyBg = "yellow";
      errBg = "red";
      errFg = "white";
      chipFg = "white";
      timeBg = "white";
      timeFg = "black";
    };
    # 单色：只用黑白两个块，改动才上黄色。
    mono = {
      osBg = "white";
      osFg = "black";
      dirBg = "black";
      dirFg = "white";
      gitBg = "white";
      gitFg = "black";
      dirtyBg = "yellow";
      errBg = "red";
      errFg = "white";
      chipFg = "white";
      timeBg = "black";
      timeFg = "white";
    };
  };
  p = palettes.${palette};
in
''
  "$schema" = 'https://starship.rs/config-schema.json'
  add_newline = true

  format = """
  [${startCap}](fg:${p.osBg})\
  [ $os ](bg:${p.osBg} fg:${p.osFg})\
  [${sep}](bg:${p.dirBg} fg:${p.osBg})\
  $directory\
  [${sep}](bg:${p.gitBg} fg:${p.dirBg})\
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
  style = 'bg:${p.osBg} fg:${p.osFg}'
  format = '[ $symbol ]($style)'
  [os.symbols]
  Macos = '${osIcon}'

  [directory]
  style = 'bg:${p.dirBg} fg:${p.dirFg}'
  format = '[ ${folder} $path ]($style)'
  truncation_length = 4
  truncation_symbol = '…/'
  truncate_to_repo = false

  [git_branch]
  symbol = '${gitIcon} ${branchIcon} '
  style = 'bg:${p.gitBg} fg:${p.gitFg}'
  format = '[ $symbol$branch ]($style)'

  # 整段被 (...) 包住，没有改动时连分隔符一起消失，不会留下空黄块。
  [git_status]
  style = 'bg:${p.dirtyBg} fg:${p.gitFg}'
  format = '([${sep}](bg:${p.dirtyBg} fg:${p.gitBg})[ $all_status$ahead_behind ]($style))'

  [status]
  disabled = false
  style = 'bg:${p.errBg} fg:${p.errFg}'
  format = '[ ${fail}$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:${p.dirtyBg} fg:${p.gitFg}'
  format = '[ ${clock}$duration ]($style)'

  [kubernetes]
  disabled = false
  symbol = '${kube} '
  style = 'bg:purple fg:${p.chipFg}'
  format = '[ $symbol$context( \($namespace\)) ]($style)'

  [terraform]
  disabled = false
  symbol = '${tf} '
  style = 'bg:black fg:${p.chipFg}'
  format = '[ $symbol$workspace ]($style)'

  [aws]
  disabled = true
  symbol = '${awsIcon} '
  style = 'bg:red fg:${p.chipFg}'
  format = '[ $symbol$profile( \($region\)) ]($style)'

  [azure]
  disabled = true
  symbol = '${azureIcon} '
  style = 'bg:blue fg:${p.chipFg}'
  format = '[ $symbol$subscription ]($style)'

  [gcloud]
  disabled = true
  symbol = '${gcloudIcon} '
  style = 'bg:blue fg:${p.chipFg}'
  format = '[ $symbol$project ]($style)'

  [nix_shell]
  disabled = false
  symbol = '${nixIcon} '
  style = 'bg:blue fg:${p.gitFg}'
  format = '[ $symbol$state( \($name\)) ]($style)'

  [hostname]
  ssh_only = true
  style = 'bg:black fg:${p.chipFg}'
  format = '[ @$hostname ]($style)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:${p.timeBg} fg:${p.timeFg}'
  format = '[ ${timeIcon}$time ]($style)'

  [fill]
  symbol = ' '

  [character]
  success_symbol = '[❯](fg:green)'
  error_symbol = '[❯](fg:red)'
''
