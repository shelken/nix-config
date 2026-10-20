# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 三色块 + powerline 分隔符 + 两行）。
#
# 颜色用 ANSI 8 色名（不是 hex）：prompt 跟随终端自身调色板，不依赖 truecolor。
#
# 导出：
#   nix eval --raw --impure --expr 'builtins.toJSON (import ./home/base/core/zsh/trials/omp.nix)'
#   nix eval --raw --impure --expr 'builtins.toJSON (import ./home/base/core/zsh/trials/omp.nix { palette = "warm"; })'
{ palette ? "classic" }:
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

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

  palettes = {
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
    warm = {
      osBg = "white";
      osFg = "black";
      dirBg = "magenta";
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

  seg = attrs: {
    style = "powerline";
    powerline_symbol = sep;
  } // attrs;
  # 右侧块不再 invert：反转后分隔符只剩前景色，会画出悬空的箭头。
  # 正向绘制时每个块前导箭头 = 前一块底色，与 p10k 的衔接一致。
  rseg = seg;
in
{
  "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
  version = 3;
  final_space = true;
  async = true;

  transient_prompt = {
    background = "transparent";
    foreground = "green";
    template = "❯ ";
  };

  blocks = [
    {
      type = "prompt";
      alignment = "left";
      segments = [
        (seg {
          type = "os";
          foreground = p.osFg;
          background = p.osBg;
          template = " {{ .Icon }} ";
        })
        (seg {
          type = "path";
          foreground = p.dirFg;
          background = p.dirBg;
          template = " ${folder} {{ .Path }} ";
          properties.style = "unique";
        })
        (seg {
          type = "git";
          foreground = p.gitFg;
          background = p.gitBg;
          background_templates = [
            "{{ if or (.Working.Changed) (.Staging.Changed) }}${p.dirtyBg}{{ end }}"
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
        (rseg {
          type = "status";
          foreground = p.errFg;
          background = p.errBg;
          template = " ${fail}{{ .Code }} ";
        })
        (rseg {
          type = "executiontime";
          foreground = p.gitFg;
          background = p.dirtyBg;
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        })
        (rseg {
          type = "kubectl";
          foreground = p.chipFg;
          background = "magenta";
          template = " ${kube}{{ .Context }} ";
          properties.parse_kubeconfig = true;
        })
        (rseg {
          type = "terraform";
          foreground = p.chipFg;
          background = "black";
          template = " ${tf}{{ .WorkspaceName }} ";
        })
        (rseg {
          type = "nix-shell";
          foreground = p.gitFg;
          background = "blue";
          template = " ${nixIcon}{{ .Type }} ";
        })
        (rseg {
          type = "time";
          foreground = p.timeFg;
          background = p.timeBg;
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
          foreground = "green";
          foreground_templates = [ "{{ if gt .Code 0 }}red{{ end }}" ];
          template = "❯";
        }
      ];
    }
  ];
}
