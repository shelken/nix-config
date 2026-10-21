{
  lib,
  catppuccin,
  myvars,
  ...
}:
let
  inherit (myvars.catppuccin) accent flavor;
  paletteSource = (lib.importJSON "${catppuccin}/pkgs/sources.json").palette;
  palette = builtins.fetchTarball {
    url = "https://github.com/catppuccin/palette/archive/${paletteSource.rev}.tar.gz";
    sha256 = paletteSource.hash;
  };
  colors = (lib.importJSON "${palette}/palette.json").${flavor}.colors;

  # Nix 字符串不支持 \u 转义；用 JSON 解析得到字形，避免源码里出现不可见字符。
  glyph = code: builtins.fromJSON "\"\\u${code}\"";
  cap = glyph "E0BA";
  sep = glyph "E0BC";
  end = glyph "E0B0";
  rcap = glyph "E0B2";
in
{
  # 不用 catppuccin.starship 与 catppuccin.sources.*：它们都是需要构建的 derivation（IFD），
  # 在 macOS 上求值 Linux 主机（just deploy pve155 等）需要 Linux builder，求值直接失败。
  # 色板改为求值期用 builtins.fetchTarball 取 catppuccin/palette，rev/hash 读 catppuccin
  # flake 自带的 sources.json，随 flake update 同步；颜色名与官方预设一致。
  catppuccin.starship.enable = false;

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      palette = "catppuccin_${flavor}";
      palettes."catppuccin_${flavor}" = lib.mapAttrs (_: c: c.hex) colors;

      # 两行：第 1 行 左 [os 目录 git] ... 右 [主机名 nix_shell 时间]，第 2 行 ❯。
      # zsh 的 right_format 落在最后一行，所以右侧用 $fill 放进第 1 行。
      format = lib.concatStrings [
        "[${cap}](fg:${accent})"
        "$os"
        "[${sep}](bg:blue fg:${accent})"
        "$directory"
        "$git_branch"
        "$git_status"
        "\${custom.end_nogit}"
        "\${custom.end_clean}"
        "$fill"
        "[${rcap}](fg:surface1)"
        "$status"
        "$cmd_duration"
        "$hostname"
        "$nix_shell"
        "\${custom.time_cap}"
        "$time"
        "[${sep}](fg:lavender)"
        "\n$character"
      ];

      fill.symbol = " ";

      os = {
        disabled = false;
        style = "bg:${accent} fg:crust";
        format = "[ $symbol ]($style)";
        symbols = {
          Macos = "🤘";
          NixOS = "🤘";
        };
      };

      directory = {
        style = "bg:blue fg:crust";
        format = "[ ${glyph "F07C"} $path ]($style)";
        truncation_length = 4;
        truncation_symbol = "…/";
        truncate_to_repo = false;
        use_os_path_sep = true;
      };

      # 与 directory 的分隔符放进 git 模块：不在仓库里时不会冒出孤立的绿色箭头。
      git_branch = {
        style = "bg:green fg:crust";
        format = "[${sep}](bg:green fg:blue)[ ${glyph "F113"} ${glyph "F126"} $branch ]($style)";
      };

      # ahead/behind 并入绿色分支块（与旧 p10k 一致，先 ⇣ 后 ⇡）；黄色状态块整段被 (...) 包住，
      # 没有文件状态时黄块、分隔符、收尾箭头一起消失，所以只领先/落后时仍只有 end_clean 一个箭头。
      git_status = {
        style = "bg:yellow fg:crust";
        format = "([$ahead_behind ](bg:green fg:crust))([${sep}](bg:yellow fg:green)[ $all_status]($style)[${end}](fg:yellow))";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇣\${behind_count} ⇡\${ahead_count}";
        conflicted = "~\${count} ";
        stashed = "";
        deleted = "✘\${count} ";
        renamed = "»\${count} ";
        modified = "!\${count} ";
        typechanged = "!\${count} ";
        staged = "+\${count} ";
        untracked = "?\${count} ";
      };

      # 收尾箭头的颜色取决于 git 是否变脏，单个内置模块表达不了，用 when 条件补。
      custom = {
        end_nogit = {
          when = "! git rev-parse --git-dir >/dev/null 2>&1";
          format = "[${end}](fg:blue)";
        };
        # 判定与 git_status 的 $all_status 一致（含未跟踪）。
        end_clean = {
          when = ''git rev-parse --git-dir >/dev/null 2>&1 && test -z "$(git status --porcelain 2>/dev/null)"'';
          format = "[${end}](fg:green)";
        };
        # 不在 nix shell 里时，hostname 与 time 之间的尖角；在里面则由 nix_shell 自带。
        time_cap = {
          when = ''test -z "$IN_NIX_SHELL"'';
          format = "[${cap}](bg:surface1 fg:lavender)";
        };
      };

      status = {
        disabled = false;
        style = "bg:red fg:crust";
        format = "[ ✘$status ]($style)";
      };

      cmd_duration = {
        min_time = 3000;
        show_milliseconds = false;
        style = "bg:peach fg:crust";
        format = "[ ${glyph "F252"}$duration ]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "bg:surface1 fg:${accent}";
        format = "[ @$hostname ]($style)";
      };

      nix_shell = {
        disabled = false;
        impure_msg = "impure";
        pure_msg = "pure";
        unknown_msg = "nix";
        style = "bg:sapphire fg:crust";
        format = "[${cap}](bg:surface1 fg:sapphire)[ $state ${glyph "F313"} ]($style)[${cap}](bg:sapphire fg:lavender)";
      };

      time = {
        disabled = false;
        time_format = "%H:%M:%S";
        style = "bg:lavender fg:crust";
        format = "[ $time ${glyph "F017"} ]($style)";
      };

      character = {
        success_symbol = "[❯](bold fg:green)";
        error_symbol = "[❯](bold fg:red)";
      };
    };
  };
}
