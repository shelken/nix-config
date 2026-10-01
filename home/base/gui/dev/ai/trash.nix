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
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) (
    let
      # 在实际处理路径的位置补齐 -f，批量搬移仍只启动一个进程。
      macTrash = pkgs.darwin.trash.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace trash.m \
            --replace-fail 'BOOL arg_list = NO;' 'BOOL arg_force = NO; BOOL arg_list = NO;' \
            --replace-fail "case 'f':" "" \
            --replace-fail "case 'd':" "case 'f': arg_force = YES; break; case 'd':" \
            --replace-fail 'PrintfErr(@"trash: %s: path does not exist\n", argv[i]);' \
              'if (arg_force) continue; PrintfErr(@"trash: %s: path does not exist\n", argv[i]);'
        '';
      });

      # PATH 注入（非 alias）：非交互 / agent bash 也能命中，不依赖 expand_aliases
      rmAsTrash = pkgs.writeShellScriptBin "rm" ''
        if [ "$#" -eq 0 ]; then
          echo "usage: rm [-f | -i] [-dPRrvW] file ..." >&2
          exit 1
        fi

        end_of_options=0
        operands=()
        options=()

        for arg in "$@"; do
          if [ "$end_of_options" -eq 0 ]; then
            if [ "$arg" = "--" ]; then
              end_of_options=1
              continue
            elif [ "$arg" != "-" ] && [ "''${arg#-}" != "$arg" ]; then
              options+=("$arg")
              continue
            fi
          fi

          if [ "$arg" = "/" ]; then
            echo "rm: it is dangerous to operate recursively on '/'" >&2
            exit 1
          fi
          operands+=("$arg")
        done

        exec ${macTrash}/bin/trash "''${options[@]}" -- "''${operands[@]}"
      '';
    in
    {
      home.packages = [
        macTrash
        rmAsTrash
      ];

      programs.direnv.stdlib = ''
        for _fn in use_flake use_nix; do
          if declare -f "$_fn" >/dev/null 2>&1; then
            eval "_orig_$_fn() $(declare -f "$_fn" | sed '1d')"
            eval "$_fn() { _orig_$_fn \"\$@\" && PATH_add \"${rmAsTrash}/bin\"; }"
          fi
        done
      '';
    }
  );
}
