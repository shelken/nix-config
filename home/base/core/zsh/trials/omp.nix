# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果。
#
# 基准是本机 p10k 的真实终端输出（pty 抓取，不是文档推断）：
#   左：E0BA(白) → 🤘(白底/232) → E0BC → 目录(蓝底/254) → E0BC → git(绿底/0) → E0B0(绿)
#   右：E0B2(黑) → @mio(黑底/3) → E0BA(黑底/白) → 时间+F017(白底/0) → E0BC(白)
#
# 所有段都是 plain，分隔符用独立文本段画，颜色完全可控；powerline 样式会让
# oh-my-posh 自己补一个前导箭头，位置和配色都对不上 p10k。
#
# 颜色：背景 ANSI 0-7，前景 xterm256 索引。不依赖 truecolor。
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  cap = glyph "E0BA"; # LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  sep = glyph "E0BC"; # LEFT_SEGMENT_SEPARATOR
  end = glyph "E0B0"; # LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL
  rstart = glyph "E0B2"; # RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL
  folder = glyph "F07C";
  gitIcon = glyph "F113";
  branchIcon = glyph "F126";
  clock = glyph "F252";
  timeIcon = glyph "F017";
  kube = glyph "F10FE";
  tf = glyph "F1BB";
  nixIcon = glyph "F313";
  fail = "✘";

  osBg = "7";
  osFg = "232";
  dirBg = "4";
  dirFg = "254";
  gitBg = "2";
  gitFg = "0";
  dirtyBg = "3";
  errBg = "1";
  errFg = "3";
  timeBg = "7";
  timeFg = "0";
  chipFg = "7";

  # 左分隔符：底色 = 后一块，前景 = 前一块（与 p10k 的 E0BC 单元格一致）
  divider = prev: next: {
    type = "text";
    style = "plain";
    foreground = prev;
    background = next;
    template = sep;
  };
  # 右提示的分隔符方向相反（p10k 的 E0BA：底色 = 前一块，前景 = 后一块）
  rdivider = prev: next: {
    type = "text";
    style = "plain";
    foreground = next;
    background = prev;
    template = cap;
  };
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
          type = "text";
          style = "plain";
          foreground = osFg;
          background = osBg;
          template = " 🤘 ";
        }
        (divider osBg dirBg)
        {
          type = "path";
          style = "plain";
          foreground = dirFg;
          background = dirBg;
          template = " ${folder} {{ .Path }} ";
          properties.style = "full";
        }
        (divider dirBg gitBg)
        {
          type = "git";
          style = "plain";
          foreground = gitFg;
          background = gitBg;
          background_templates = [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}${dirtyBg}{{ end }}"
          ];
          properties.branch_icon = "";
          properties.fetch_status = true;
          template = " ${gitIcon} ${branchIcon} {{ .HEAD }}{{ if .Working.Changed }} {{ .Working.String }}{{ end }}{{ if .Staging.Changed }} {{ .Staging.String }}{{ end }} ";
        }
        {
          type = "text";
          style = "plain";
          foreground = gitBg;
          template = end;
        }
      ];
    }
    {
      type = "prompt";
      alignment = "right";
      segments = [
        {
          type = "text";
          style = "plain";
          foreground = gitFg;
          template = rstart;
        }
        {
          type = "status";
          style = "plain";
          foreground = errFg;
          background = errBg;
          template = " ${fail}{{ .Code }} ";
        }
        {
          type = "executiontime";
          style = "plain";
          foreground = gitFg;
          background = dirtyBg;
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        }
        {
          type = "kubectl";
          style = "plain";
          foreground = chipFg;
          background = dirBg;
          template = " ${kube}{{ .Context }} ";
          properties.parse_kubeconfig = true;
        }
        {
          type = "terraform";
          style = "plain";
          foreground = chipFg;
          background = "0";
          template = " ${tf}{{ .WorkspaceName }} ";
        }
        {
          type = "nix-shell";
          style = "plain";
          foreground = gitFg;
          background = dirBg;
          template = " ${nixIcon}{{ .Type }} ";
        }
        {
          type = "session";
          style = "plain";
          foreground = errFg;
          background = "0";
          template = " @{{ .HostName }} ";
        }
        (rdivider "0" timeBg)
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
