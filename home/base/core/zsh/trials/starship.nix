# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（形状）+ Catppuccin 命名色板（配色）。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取，不是文档推断）：
#   第 1 行 左：E0BA → 🤘 → E0BC → 目录 → E0BC → git → E0B0（跟随 git 底色）
#   第 1 行 右：E0B2 → [direnv ▼ ╱] @主机名 → [nix_shell] → 时间+F017 → E0BC
#   第 2 行：❯
#
# 配色沿用 Catppuccin 官方 catppuccin-powerline 预设的习惯：色块用命名色，块内文字统一 crust，
# 提示符 green/red，accent 取 vars.catppuccin.accent。
# 并入主配置后删掉本文件的 [palettes.*]：catppuccin.starship（autoEnable）会注入
# palette = "catppuccin_<flavor>"，accent 由 vars 派生。
#
# Starship 的 right_format 在 zsh 里落在最后一行，所以右侧用 $fill 放进第 1 行。
# 收尾箭头的颜色取决于 git 是否变脏，没有单模块能表达，用 custom 模块（when 条件）补。
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  # Catppuccin Macchiato；accent = vars.catppuccin.accent (pink)
  colors = {
    crust = "#181926";
    surface1 = "#494d64";
    red = "#ed8796";
    peach = "#f5a97f";
    yellow = "#eed49f";
    green = "#a6da95";
    sapphire = "#7dc4e4";
    blue = "#8aadf4";
    lavender = "#b7bdf8";
    accent = "#f5bde6";
  };
  palette = builtins.concatStringsSep "\n" (
    builtins.attrValues (builtins.mapAttrs (name: hex: "${name} = '${hex}'") colors)
  );
in
''
  "$schema" = 'https://starship.rs/config-schema.json'
  add_newline = true
  palette = 'catppuccin_macchiato'

  format = """
  [${glyph "E0BA"}](fg:accent)\
  $os\
  [${glyph "E0BC"}](bg:blue fg:accent)\
  $directory\
  $git_branch\
  $git_status\
  ''${custom.end_nogit}\
  ''${custom.end_clean}\
  $fill\
  [${glyph "E0B2"}](fg:surface1)\
  $status\
  $cmd_duration\
  $direnv\
  $hostname\
  $nix_shell\
  ''${custom.time_cap}\
  $time\
  [${glyph "E0BC"}](fg:lavender)
  $character"""

  [fill]
  symbol = ' '

  [os]
  disabled = false
  style = 'bg:accent fg:crust'
  format = '[ $symbol ]($style)'
  [os.symbols]
  Macos = '🤘'

  [directory]
  style = 'bg:blue fg:crust'
  format = '[ ${glyph "F07C"} $path ]($style)'
  truncation_length = 4
  truncation_symbol = '…/'
  truncate_to_repo = false
  use_os_path_sep = true

  # 分隔符放进 git 模块：不在仓库里时不会冒出孤立的绿色箭头。
  [git_branch]
  style = 'bg:green fg:crust'
  format = '[${glyph "E0BC"}](bg:green fg:blue)[ ${glyph "F113"} ${glyph "F126"} $branch ]($style)'

  # 整段被 (...) 包住：干净时黄块、分隔符、收尾箭头一起消失。
  [git_status]
  style = 'bg:yellow fg:crust'
  format = '([${glyph "E0BC"}](bg:yellow fg:green)[ $all_status]($style)[${glyph "E0B0"}](fg:yellow))'
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
  format = '[${glyph "E0B0"}](fg:blue)'

  # 在仓库且干净：绿色收尾箭头。判定与 git_status 的 $all_status 一致（含未跟踪）。
  [custom.end_clean]
  when = 'git rev-parse --git-dir >/dev/null 2>&1 && test -z "$(git status --porcelain 2>/dev/null)"'
  format = '[${glyph "E0B0"}](fg:green)'

  [status]
  disabled = false
  style = 'bg:red fg:crust'
  format = '[ ✘$status ]($style)'

  [cmd_duration]
  min_time = 3000
  show_milliseconds = false
  style = 'bg:peach fg:crust'
  format = '[ ${glyph "F252"}$duration ]($style)'

  [direnv]
  disabled = false
  style = 'bg:surface1 fg:accent'
  format = '[ ▼ ╱]($style)'

  # p10k 的 context 段：@主机名，本机也常显
  [hostname]
  ssh_only = false
  style = 'bg:surface1 fg:accent'
  format = '[ @$hostname ]($style)'

  # 在 nix shell 里：深灰 → 蓝 → 薰衣草；不在：深灰 → 薰衣草（由 time_cap 补）。
  [nix_shell]
  disabled = false
  impure_msg = 'impure'
  pure_msg = 'pure'
  unknown_msg = 'nix'
  style = 'bg:sapphire fg:crust'
  format = '[${glyph "E0BA"}](bg:surface1 fg:sapphire)[ $state ${glyph "F313"} ]($style)[${glyph "E0BA"}](bg:sapphire fg:lavender)'

  [custom.time_cap]
  when = 'test -z "$IN_NIX_SHELL"'
  format = '[${glyph "E0BA"}](bg:surface1 fg:lavender)'

  [time]
  disabled = false
  time_format = '%H:%M:%S'
  style = 'bg:lavender fg:crust'
  format = '[ $time ${glyph "F017"} ]($style)'

  [character]
  success_symbol = '[❯](bold fg:green)'
  error_symbol = '[❯](bold fg:red)'

  [palettes.catppuccin_macchiato]
  ${palette}
''
