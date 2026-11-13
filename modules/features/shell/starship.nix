# starship：提示符
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.starship ];

  flake.modules.homeManager.starship =
    {
      lib,
      myvars,
      ...
    }:
    let
      inherit (myvars.catppuccin) accent;

      # Nix 字符串不支持 \u 转义；用 JSON 解析得到字形，避免源码里出现不可见字符。
      glyph = code: builtins.fromJSON "\"\\u${code}\"";
      cap = glyph "E0BA";
      sep = glyph "E0BC";
      end = glyph "E0B0";
      k8s = builtins.fromJSON ''"\udb84\udcfe"''; # nf-md-kubernetes，超出 BMP，需代理对
      # 块是否出现取决于运行时状态，分隔符的底色一律取 prev_bg（前一块的背景，打头时为终端底色）。
      rhead = color: "[${glyph "E0B2"}](bg:prev_bg fg:${color})";
      rslant = color: "[${cap}](bg:prev_bg fg:${color})";
    in
    {
      # Starship 不提供 zsh 的 transient prompt：行编辑结束时把提示符重绘成单行 ❯，屏幕上只留最新的完整 bar；
      # 旧 bar 不再占满整行，窗口缩放时也不会被终端重排成残块。
      programs.zsh.initContent = ''
        autoload -Uz add-zle-hook-widget add-zsh-hook
        _starship_transient_prompt=$'\n'
        _starship_transient_prompt+='$(starship module character --status="''${STARSHIP_CMD_STATUS:-}")'
        _starship_transient_finish() {
          [[ $PROMPT == "$_starship_transient_prompt" ]] && return
          _starship_full_prompt=$PROMPT _starship_full_rprompt=$RPROMPT
          PROMPT=$_starship_transient_prompt RPROMPT=
          zle .reset-prompt
        }
        _starship_transient_restore() {
          [[ $PROMPT == "$_starship_transient_prompt" ]] || return 0
          PROMPT=$_starship_full_prompt RPROMPT=$_starship_full_rprompt
        }
        add-zle-hook-widget line-finish _starship_transient_finish
        # Ctrl-C 中断行编辑时不走 line-finish。
        TRAPINT() {
          zle && _starship_transient_finish
          return $(( 128 + $1 ))
        }
        add-zsh-hook precmd _starship_transient_restore
      '';

      # 色板与 palette 由 catppuccin.starship（autoEnable）注入，这里只引用颜色名。
      programs.starship = {
        enable = true;
        settings = {
          add_newline = true;

          # 两行：第 1 行 左 [os 目录 git] ... 右 [主机名 nix_shell 时间]，第 2 行 ❯。
          # zsh 的 right_format 落在最后一行，所以右侧用 $fill 放进第 1 行。
          format = lib.concatStrings [
            "[${cap}](fg:${accent})"
            "$os"
            "[${sep}](bg:blue fg:${accent})"
            "$directory"
            "$git_branch"
            "$git_commit"
            "$git_state"
            "$git_status"
            # 收尾箭头随最后一块变色：非仓库蓝、干净绿、有改动黄。
            "[${end}](fg:prev_bg)"
            "$fill"
            "$status"
            "$cmd_duration"
            "$jobs"
            "$direnv"
            "$kubernetes"
            "$hostname"
            "$nix_shell"
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

          # detached HEAD 时 $branch 为 HEAD，hash 接在后面。
          git_commit.format = "[$hash ](bg:green fg:crust)";

          git_state = {
            style = "bg:green fg:crust bold";
            format = "[$state( $progress_current/$progress_total) ]($style)";
          };

          # ahead/behind 并入绿色分支块（与旧 p10k 一致，先 ⇣ 后 ⇡）；黄色状态块整段被 (...) 包住，
          # 没有文件状态时黄块与分隔符一起消失。
          git_status = {
            style = "bg:yellow fg:crust";
            format = "([$ahead_behind ](bg:green fg:crust))([${sep}](bg:yellow fg:green)[ $all_status]($style))";
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

          status = {
            disabled = false;
            style = "bg:red fg:crust";
            format = "${rhead "red"}[ ${glyph "F00D"} $status ]($style)";
          };

          cmd_duration = {
            min_time = 3000;
            show_milliseconds = false;
            style = "bg:peach fg:crust";
            format = "${rhead "peach"}[ ${glyph "F252"}$duration ]($style)";
          };

          jobs = {
            number_threshold = 1;
            format = "${rhead "teal"}[ ${glyph "F013"} $number ](bg:teal fg:crust)";
          };

          # 只在 .envrc 未允许或被拒绝时出现：allowed_msg 为空，整段 (...) 不渲染。
          direnv = {
            disabled = false;
            allowed_msg = "";
            format = "(${rhead "yellow"}[ direnv $allowed ](bg:yellow fg:crust))";
          };

          kubernetes = {
            disabled = false;
            format = "${rhead "mauve"}[ ${k8s} $context( \\($namespace\\)) ](bg:mauve fg:crust)";
          };

          hostname = {
            ssh_only = false;
            style = "bg:surface1 fg:${accent}";
            format = "${rhead "surface1"}[ @$hostname ]($style)";
          };

          nix_shell = {
            disabled = false;
            impure_msg = "impure";
            pure_msg = "pure";
            unknown_msg = "nix";
            # `nix shell` 不设 IN_NIX_SHELL，靠 PATH 中的 /nix/store 识别。
            heuristic = true;
            style = "bg:sapphire fg:crust";
            format = "${rslant "sapphire"}[ $state ${glyph "F313"} ]($style)";
          };

          time = {
            disabled = false;
            time_format = "%H:%M:%S";
            style = "bg:lavender fg:crust";
            format = "${rslant "lavender"}[ $time ${glyph "F017"} ]($style)";
          };

          character = {
            success_symbol = "[❯](bold fg:green)";
            error_symbol = "[❯](bold fg:red)";
          };
        };
      };
    };
}
