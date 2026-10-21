# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（形状）+ Catppuccin 命名色（配色）。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取）：
#   第 1 行 左：E0BA → 🤘 → E0BC → 目录 → E0BC → git → E0B0（跟随 git 底色）
#   第 1 行 右：E0B2 → @主机名 → [nix_shell] → 时间+F017 → E0BC
#   第 2 行：❯
#
# 配色沿用 Catppuccin 官方预设的习惯：色块用命名色，块内文字统一 crust，
# 提示符 green/red，accent 取 vars.catppuccin.accent。并入主配置时 colors 改由
# config.catppuccin.sources.palette 的 palette.json 按 flavor 派生（kitty/pi 主题同一做法）。
#
# 结构：OMP 的 powerline 样式会在段后自动补收尾符号，且下一段是 plain 时丢失底色，
# 复现不了 p10k 的箭头。所以内容段全用 plain，分隔符与收尾箭头用模板内联颜色
# <fg,bg>…</> 显式指定，git 脏/净时随之变色。
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  cap = glyph "E0BA"; # LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL / RIGHT_SEGMENT_SEPARATOR
  sep = glyph "E0BC"; # LEFT_SEGMENT_SEPARATOR / RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL
  end = glyph "E0B0"; # LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL
  rcap = glyph "E0B2"; # RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  folder = glyph "F07C";
  gitIcon = glyph "F113";
  branchIcon = glyph "F126";
  clock = glyph "F252";
  timeIcon = glyph "F017";
  nixIcon = glyph "F313";
  fail = "✘"; # p10k STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION

  # Catppuccin Macchiato；accent = vars.catppuccin.accent (pink)
  c = {
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

  dirty = "or .Working.Changed .Staging.Changed";
  gitColor = "{{ if ${dirty} }}${c.yellow}{{ else }}${c.green}{{ end }}";
  inNix = ".Env.IN_NIX_SHELL";
in
{
  "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
  version = 3;
  final_space = true;
  async = false;

  transient_prompt = {
    background = "transparent";
    foreground = c.green;
    template = "❯ ";
  };

  blocks = [
    {
      type = "prompt";
      alignment = "left";
      segments = [
        {
          type = "os";
          style = "diamond";
          leading_diamond = cap;
          foreground = c.crust;
          background = c.accent;
          template = " 🤘 ";
        }
        {
          type = "path";
          style = "plain";
          foreground = c.crust;
          background = c.blue;
          template = "<${c.accent}>${sep}</> ${folder} {{ .Path }} ";
          properties.style = "full";
        }
        {
          type = "git";
          style = "plain";
          foreground = c.crust;
          background = c.green;
          background_templates = [ "{{ if ${dirty} }}${c.yellow}{{ end }}" ];
          properties.branch_icon = "";
          properties.fetch_status = true;
          template = "<${c.blue}>${sep}</> ${gitIcon} ${branchIcon} {{ .HEAD }}{{ if gt .Working.Modified 0 }} !{{ .Working.Modified }}{{ end }}{{ if gt .Working.Untracked 0 }} ?{{ .Working.Untracked }}{{ end }}{{ if gt .Staging.Modified 0 }} +{{ .Staging.Modified }}{{ end }} <${gitColor},transparent>${end}</>";
        }
        {
          type = "text";
          style = "plain";
          foreground = c.blue;
          template = "{{ if not (.Segments.Contains \"Git\") }}${end}{{ end }}";
        }
      ];
    }
    {
      type = "prompt";
      alignment = "right";
      segments = [
        {
          type = "status";
          style = "diamond";
          leading_diamond = rcap;
          foreground = c.crust;
          background = c.red;
          template = " ${fail}{{ .Code }} ";
        }
        {
          type = "executiontime";
          style = "diamond";
          leading_diamond = rcap;
          foreground = c.crust;
          background = c.peach;
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        }
        {
          type = "session";
          style = "diamond";
          leading_diamond = rcap;
          foreground = c.accent;
          background = c.surface1;
          template = " @{{ .HostName }} ";
        }
        {
          type = "text";
          style = "plain";
          foreground = c.sapphire;
          background = c.surface1;
          template = "{{ if ${inNix} }}${cap}{{ end }}";
        }
        {
          type = "nix-shell";
          style = "plain";
          foreground = c.crust;
          background = c.sapphire;
          template = " {{ .Type }} ${nixIcon} ";
        }
        {
          type = "text";
          style = "plain";
          foreground = c.lavender;
          background = c.surface1;
          background_templates = [ "{{ if ${inNix} }}${c.sapphire}{{ end }}" ];
          template = cap;
        }
        {
          type = "time";
          style = "plain";
          foreground = c.crust;
          background = c.lavender;
          template = " {{ .CurrentDate | date .Format }} ${timeIcon} ";
          properties.time_format = "15:04:05";
        }
        {
          type = "text";
          style = "plain";
          foreground = c.lavender;
          template = sep;
        }
      ];
    }
    {
      type = "prompt";
      alignment = "left";
      newline = true;
      segments = [
        {
          type = "text";
          style = "plain";
          foreground = c.green;
          foreground_templates = [ "{{ if gt .Code 0 }}${c.red}{{ end }}" ];
          template = "❯";
        }
      ];
    }
  ];
}
