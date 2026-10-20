# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取）：
#   左：E0BA(白) → 🤘(白底/232) → E0BC → 目录(蓝底/254) → E0BC → git(绿底/0) → E0B0
#   右：@mio(黑底/3) → E0BA → 时间+时钟(白底/0) → E0BC
#
# 颜色写死 Catppuccin Macchiato 的 hex（wiki §2 的决策）：prompt 在 kitty 和
# herdrm 里显示完全一致，不再依赖宿主终端的 16 色映射。
# 前景 232/254/76 是 xterm256 索引——16-255 不被任何主题重映射，两边同样一致。
#
# 结构：左块用 powerline（分隔符自动跟随 git 段的动态底色）；右块用
# powerline + invert_powerline（p10k 右侧分隔符方向相反，invert 正好复刻）。
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  cap = glyph "E0BA"; # LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  sep = glyph "E0BC"; # LEFT_SEGMENT_SEPARATOR
  end = glyph "E0B0"; # LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL
  folder = glyph "F07C";
  gitIcon = glyph "F113";
  branchIcon = glyph "F126";
  clock = glyph "F252";
  timeIcon = glyph "F017";
  nixIcon = glyph "F313";
  fail = "✘"; # p10k STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION

  # Catppuccin Macchiato（kitty 同源）
  osBg = "#b8c0e0"; # ANSI 7
  osFg = "232";
  dirBg = "#8aadf4"; # ANSI 4
  dirFg = "254";
  gitBg = "#a6da95"; # ANSI 2
  gitFg = "#494d64"; # ANSI 0
  dirtyBg = "#eed49f"; # ANSI 3
  errBg = "#ed8796"; # ANSI 1
  errFg = "#eed49f"; # ANSI 3
  timeBg = "#b8c0e0"; # ANSI 7
  timeFg = "#494d64"; # ANSI 0
in
{
  "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
  version = 3;
  final_space = true;
  async = true;

  transient_prompt = {
    background = "transparent";
    foreground = "76";
    template = "❯ ";
  };

  blocks = [
    {
      type = "prompt";
      alignment = "left";
      segments = [
        {
          type = "text";
          style = "plain";
          foreground = osBg;
          template = cap;
        }
        {
          type = "os";
          style = "plain";
          foreground = osFg;
          background = osBg;
          template = " 🤘 ";
        }
        {
          type = "path";
          style = "powerline";
          powerline_symbol = sep;
          foreground = dirFg;
          background = dirBg;
          template = " ${folder} {{ .Path }} ";
          properties.style = "full";
        }
        {
          type = "git";
          style = "powerline";
          powerline_symbol = sep;
          foreground = gitFg;
          background = gitBg;
          background_templates = [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}${dirtyBg}{{ end }}"
          ];
          properties.branch_icon = "";
          properties.fetch_status = true;
          template = " ${gitIcon} ${branchIcon} {{ .HEAD }}{{ if gt .Working.Modified 0 }} !{{ .Working.Modified }}{{ end }}{{ if gt .Working.Untracked 0 }} ?{{ .Working.Untracked }}{{ end }}{{ if gt .Staging.Modified 0 }} +{{ .Staging.Modified }}{{ end }} ";
        }
      ];
    }
    {
      type = "prompt";
      alignment = "right";
      segments = [
        {
          type = "status";
          style = "powerline";
          invert_powerline = true;
          powerline_symbol = cap;
          foreground = errFg;
          background = errBg;
          template = " ${fail}{{ .Code }} ";
        }
        {
          type = "executiontime";
          style = "powerline";
          invert_powerline = true;
          powerline_symbol = cap;
          foreground = gitFg;
          background = dirtyBg;
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        }
        {
          type = "session";
          style = "powerline";
          invert_powerline = true;
          powerline_symbol = cap;
          foreground = errFg;
          background = gitFg;
          template = " @{{ .HostName }} ";
        }
        {
          type = "nix-shell";
          style = "powerline";
          invert_powerline = true;
          powerline_symbol = cap;
          foreground = gitFg;
          background = dirBg;
          template = " ${nixIcon}{{ .Type }} ";
        }
        {
          type = "time";
          style = "powerline";
          invert_powerline = true;
          powerline_symbol = cap;
          foreground = timeFg;
          background = timeBg;
          template = " {{ .CurrentDate | date .Format }} ${timeIcon} ";
          properties.time_format = "15:04:05";
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
          foreground = "76";
          foreground_templates = [ "{{ if gt .Code 0 }}196{{ end }}" ];
          template = "❯";
        }
      ];
    }
  ];
}
