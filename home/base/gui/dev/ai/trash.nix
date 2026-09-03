{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.shelken.dev.ai;
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    home.packages =
      let
        # ali-rantakari/trash：系统 API → Finder 废纸篓；静默接受 rm 的 -rf 等 flag
        # 用绝对路径，避免和 macOS 15+ 自带 /usr/bin/trash 撞名
        macTrash = "${pkgs.darwin.trash}/bin/trash";

        # PATH 注入（非 alias）：非交互 / agent bash 也能命中，不依赖 expand_aliases
        # 作为 AI agent 命令执行环境的安全兜底，包装层解决 ali-rantakari/trash 在路径不存在时报错退出、缺乏 -f 静默语义的痛点
        rmAsTrash = pkgs.writeShellScriptBin "rm" ''
          if [ "$#" -eq 0 ]; then
            echo "usage: rm [-f | -i] [-dPRrvW] file ..." >&2
            exit 1
          fi

          has_force=0
          end_of_options=0
          has_missing=0
          valid_files=()
          options=()

          for arg in "$@"; do
            if [ "$end_of_options" -eq 0 ]; then
              if [ "$arg" = "--" ]; then
                end_of_options=1
                continue
              elif [ "$arg" != "-" ] && [ "''${arg#-}" != "$arg" ]; then
                options+=("$arg")
                case "$arg" in
                  *f*) has_force=1 ;;
                esac
                continue
              fi
            fi

            # 存在性检查：[ -e ] 实体文件/目录存在，[ -L ] 软链接（包含失效软链接）存在
            if [ -e "$arg" ] || [ -L "$arg" ]; then
              if [ "$arg" = "/" ]; then
                echo "rm: it is dangerous to operate recursively on '/'" >&2
                exit 1
              fi
              valid_files+=("$arg")
            else
              has_missing=1
              if [ "$has_force" -eq 0 ]; then
                echo "rm: $arg: No such file or directory" >&2
              fi
            fi
          done

          # 若存在缺失文件且未指定 -f，按 POSIX 规范报错退出（兼顾部分文件已移入废纸篓）
          if [ "$has_missing" -eq 1 ] && [ "$has_force" -eq 0 ]; then
            if [ "''${#valid_files[@]}" -gt 0 ]; then
              ${macTrash} "''${options[@]}" -- "''${valid_files[@]}" || true
            fi
            exit 1
          fi

          # 若所有目标均不存在且有 -f，直接静默退出（不启动昂贵的 Cocoa trash 进程）
          if [ "''${#valid_files[@]}" -eq 0 ]; then
            exit 0
          fi

          exec ${macTrash} "''${options[@]}" -- "''${valid_files[@]}"
        '';
      in
      [
        pkgs.darwin.trash
        rmAsTrash
      ];
  };
}
