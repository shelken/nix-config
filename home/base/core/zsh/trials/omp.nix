# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 色块 + powerline 分隔符 + 两行）。
#
# 颜色直接取 p10k 的运行时值：
#   背景用 ANSI 0-7（跟随终端调色板），前景用 xterm256 索引（232/254/0/76/196）。
# 256 色是标准调色板，kitty 和 herdrm 显示完全一致，不依赖 truecolor。
#
# 导出：
#   nix eval --raw --impure --expr 'builtins.toJSON (import ./home/base/core/zsh/trials/omp.nix)'
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  # 字形取自 p10k 在本机的实际渲染输出。
  sep = glyph "E0BC";
  folder = glyph "F07C";
  gitIcon = glyph "F113";
  branchIcon = glyph "F126";
  clock = glyph "F252";
  timeIcon = glyph "F017";
  kube = glyph "F10FE";
  tf = glyph "F1BB";
  nixIcon = glyph "F313";
  fail = glyph "F00D";

  # p10k 的实际配色（渲染核对过）。
  osBg = "7";
  osFg = "232";
  dirBg = "4";
  dirFg = "254";
  gitBg = "2"; # 干净时
  gitFg = "0";
  dirtyBg = "3"; # 有改动时整段变黄
  errBg = "1";
  errFg = "3";
  timeBg = "7";
  timeFg = "0";
  chipFg = "7";

  seg = attrs: {
    style = "powerline";
    powerline_symbol = sep;
  } // attrs;
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
        (seg {
          type = "os";
          foreground = osFg;
          background = osBg;
          template = " {{ .Icon }} ";
        })
        (seg {
          type = "path";
          foreground = dirFg;
          background = dirBg;
          template = " ${folder} {{ .Path }} ";
          properties.style = "unique";
        })
        (seg {
          type = "git";
          foreground = gitFg;
          background = gitBg;
          background_templates = [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}${dirtyBg}{{ end }}"
          ];
          properties.branch_icon = "";
          properties.fetch_status = true;
          template = " ${gitIcon} ${branchIcon} {{ .HEAD }}{{ if .Working.Changed }} {{ .Working.String }}{{ end }}{{ if .Staging.Changed }} {{ .Staging.String }}{{ end }} ";
        })
      ];
    }
    {
      type = "prompt";
      alignment = "right";
      segments = [
        (seg {
          type = "status";
          foreground = errFg;
          background = errBg;
          template = " ${fail}{{ .Code }} ";
        })
        (seg {
          type = "executiontime";
          foreground = gitFg;
          background = dirtyBg;
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        })
        (seg {
          type = "kubectl";
          foreground = chipFg;
          background = dirBg;
          template = " ${kube}{{ .Context }} ";
          properties.parse_kubeconfig = true;
        })
        (seg {
          type = "terraform";
          foreground = chipFg;
          background = "0";
          template = " ${tf}{{ .WorkspaceName }} ";
        })
        (seg {
          type = "nix-shell";
          foreground = gitFg;
          background = dirBg;
          template = " ${nixIcon}{{ .Type }} ";
        })
        (seg {
          type = "time";
          foreground = timeFg;
          background = timeBg;
          template = " ${timeIcon}{{ .CurrentDate | date .Format }} ";
          properties.time_format = "15:04:05";
        })
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
