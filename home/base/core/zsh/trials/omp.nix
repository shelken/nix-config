# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取）：
#   第 1 行 左：E0BA(白) → 🤘(白底/232) → E0BC → 目录(蓝底/254) → E0BC → git → E0B0(跟随 git 底色)
#   第 1 行 右：E0B2 → @mio(黑底/黄) → [nix_shell(蓝底)] → 时间+F017(白底) → E0BC
#   第 2 行：❯
#
# 颜色写死 Catppuccin Macchiato 的 hex（Catppuccin 官方 OMP/Starship 预设同样用 hex）：
# kitty 和 herdrm 里显示一致。前景 232/254/76/196 是 xterm256 索引，主题不会重映射。
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

  dirty = "or .Working.Changed .Staging.Changed";
  gitColor = "{{ if ${dirty} }}${dirtyBg}{{ else }}${gitBg}{{ end }}";
  inNix = ".Env.IN_NIX_SHELL";
in
{
  "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
  version = 3;
  final_space = true;
  async = false;

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
          type = "os";
          style = "diamond";
          leading_diamond = cap;
          foreground = osFg;
          background = osBg;
          template = " 🤘 ";
        }
        {
          type = "path";
          style = "plain";
          foreground = dirFg;
          background = dirBg;
          template = "<${osBg}>${sep}</> ${folder} {{ .Path }} ";
          properties.style = "full";
        }
        {
          type = "git";
          style = "plain";
          foreground = gitFg;
          background = gitBg;
          background_templates = [ "{{ if ${dirty} }}${dirtyBg}{{ end }}" ];
          properties.branch_icon = "";
          properties.fetch_status = true;
          template = "<${dirBg}>${sep}</> ${gitIcon} ${branchIcon} {{ .HEAD }}{{ if gt .Working.Modified 0 }} !{{ .Working.Modified }}{{ end }}{{ if gt .Working.Untracked 0 }} ?{{ .Working.Untracked }}{{ end }}{{ if gt .Staging.Modified 0 }} +{{ .Staging.Modified }}{{ end }} <${gitColor},transparent>${end}</>";
        }
        {
          type = "text";
          style = "plain";
          foreground = dirBg;
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
          foreground = errFg;
          background = errBg;
          template = " ${fail}{{ .Code }} ";
        }
        {
          type = "executiontime";
          style = "diamond";
          leading_diamond = rcap;
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
          style = "diamond";
          leading_diamond = rcap;
          foreground = errFg;
          background = gitFg;
          template = " @{{ .HostName }} ";
        }
        {
          type = "text";
          style = "plain";
          foreground = dirBg;
          background = gitFg;
          template = "{{ if ${inNix} }}${cap}{{ end }}";
        }
        {
          type = "nix-shell";
          style = "plain";
          foreground = gitFg;
          background = dirBg;
          template = " {{ .Type }} ${nixIcon} ";
        }
        {
          type = "text";
          style = "plain";
          foreground = timeBg;
          background = gitFg;
          background_templates = [ "{{ if ${inNix} }}${dirBg}{{ end }}" ];
          template = cap;
        }
        {
          type = "time";
          style = "plain";
          foreground = timeFg;
          background = timeBg;
          template = " {{ .CurrentDate | date .Format }} ${timeIcon} ";
          properties.time_format = "15:04:05";
        }
        {
          type = "text";
          style = "plain";
          foreground = timeBg;
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
          foreground = "76";
          foreground_templates = [ "{{ if gt .Code 0 }}196{{ end }}" ];
          template = "❯";
        }
      ];
    }
  ];
}
