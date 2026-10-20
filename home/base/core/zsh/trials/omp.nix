# 复刻 home/base/core/zsh/p10k/p10k.zsh 的最终效果（rainbow 三色块 + slanted 分隔符 + 两行）。
#
# 与 p10k 的已知差异：
#   - 没有 show-on-command（kube/terraform/aws/… 在相应环境一直显示）。
#   - dir 的子段分隔符用 ╱，但目录层级由 OMP 的 folder_separator_icon 决定。
#   - git 变脏时 p10k 让整段变黄，这里整段用 background_templates 同样变黄。
#
# 导出：
#   nix eval --raw --impure --expr 'builtins.toJSON (import ./home/base/core/zsh/trials/omp.nix)' > /tmp/prompt-trial/omp.json
let
  glyph = code: builtins.fromJSON "\"\\u${code}\"";

  sep = glyph "E0BC"; # p10k LEFT_SEGMENT_SEPARATOR
  folder = glyph "F115";
  branch = glyph "F126";
  clock = glyph "F252";
  kube = glyph "F10FE";
  tf = glyph "F1BB";
  awsIcon = glyph "F270";
  azureIcon = glyph "EBD8";
  gcloudIcon = glyph "F02AD";
  nixIcon = glyph "F313";
  timeIcon = glyph "F017";
  fail = glyph "F00D";

  seg =
    attrs:
    {
      style = "powerline";
      powerline_symbol = sep;
    }
    // attrs;

  # 右侧块的分隔符方向与左侧相反（p10k 用 E0BA）。
  rseg = attrs: seg (attrs // { invert_powerline = true; });
in
{
  "$schema" = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
  version = 3;
  final_space = true;
  async = true;

  transient_prompt = {
    background = "transparent";
    foreground = "#5fd700";
    template = "❯ ";
  };

  blocks = [
    {
      type = "prompt";
      alignment = "left";
      segments = [
        (seg {
          type = "os";
          foreground = "#080808";
          background = "#b8c0e0";
          template = " 🤘 ";
        })
        (seg {
          type = "path";
          foreground = "#e4e4e4";
          background = "#8aadf4";
          template = " ${folder}{{ .Path }} ";
          properties.folder_separator_icon = "╱";
        })
        (seg {
          type = "git";
          foreground = "#494d64";
          background = "#a6da95";
          background_templates = [ "{{ if or (.Working.Changed) (.Staging.Changed) }}#eed49f{{ end }}" ];
          template = " ${branch}{{ .HEAD }}{{ if .Working.Changed }} {{ .Working.String }}{{ end }}{{ if .Staging.Changed }} {{ .Staging.String }}{{ end }} ";
        })
      ];
    }
    {
      type = "prompt";
      alignment = "right";
      segments = [
        (rseg {
          type = "status";
          foreground = "#eed49f";
          background = "#ed8796";
          template = " ${fail}{{ .Code }} ";
        })
        (rseg {
          type = "executiontime";
          foreground = "#494d64";
          background = "#eed49f";
          template = " ${clock}{{ .FormattedMs }} ";
          properties = {
            threshold = 3000;
            style = "round";
          };
        })
        (rseg {
          type = "kubectl";
          foreground = "#b8c0e0";
          background = "#c6a0f6";
          template = " ${kube}{{ .Context }} ";
          properties.parse_kubeconfig = true;
        })
        (rseg {
          type = "terraform";
          foreground = "#b8c0e0";
          background = "#494d64";
          template = " ${tf}{{ .WorkspaceName }} ";
        })
        (rseg {
          type = "aws";
          foreground = "#b8c0e0";
          background = "#ed8796";
          template = " ${awsIcon}{{ .Profile }}{{ if .Region }}@{{ .Region }}{{ end }} ";
        })
        (rseg {
          type = "az";
          foreground = "#b8c0e0";
          background = "#8aadf4";
          template = " ${azureIcon}{{ .Name }} ";
        })
        (rseg {
          type = "gcp";
          foreground = "#b8c0e0";
          background = "#8aadf4";
          template = " ${gcloudIcon}{{ .Project }} ";
        })
        (rseg {
          type = "nix-shell";
          foreground = "#494d64";
          background = "#8aadf4";
          template = " ${nixIcon}{{ .Type }} ";
        })
        (rseg {
          type = "time";
          foreground = "#494d64";
          background = "#b8c0e0";
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
          foreground = "#5fd700";
          foreground_templates = [ "{{ if gt .Code 0 }}#ff0000{{ end }}" ];
          template = "❯";
        }
      ];
    }
  ];
}
