{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.trash ];

  flake.modules.homeManager.trash =
    {
      pkgs,
      lib,
      ...
    }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
        let
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

          rmAsTrash = pkgs.writeShellScriptBin "rm" ''
            if [ -n "''${NIX_BUILD_TOP:-}" ] || [ "$(id -u)" -eq 0 ]; then
              exec /bin/rm "$@"
            fi

            if [ "$#" -eq 0 ]; then
              echo "usage: rm [-f | -i] [-dPRrvWx] file ..." >&2
              exit 1
            fi

            end_of_options=0
            has_force=0
            has_verbose=0
            operands=()
            options=()

            for arg in "$@"; do
              if [ "$end_of_options" -eq 0 ]; then
                case "$arg" in
                  --)
                    end_of_options=1
                    continue
                    ;;
                  --force)
                    has_force=1
                    continue
                    ;;
                  --verbose)
                    has_verbose=1
                    continue
                    ;;
                  --recursive|--dir|--interactive|--interactive=*|--one-file-system|--no-preserve-root|--preserve-root|--preserve-root=*)
                    continue
                    ;;
                  --*)
                    printf 'rm: unrecognized option %s\n' "$arg" >&2
                    printf 'usage: rm [-f | -i] [-dPRrvWx] file ...\n' >&2
                    exit 1
                    ;;
                  -*)
                    if [ "$arg" != "-" ]; then
                      flags=''${arg#-}
                      for ((i = 0; i < ''${#flags}; i++)); do
                        ch=''${flags:i:1}
                        case "$ch" in
                          f) has_force=1 ;;
                          v) has_verbose=1 ;;
                          r|R|d|i|I|P|W|x) ;;
                          *)
                            printf 'rm: illegal option -- %s\n' "$ch" >&2
                            printf 'usage: rm [-f | -i] [-dPRrvWx] file ...\n' >&2
                            exit 1
                            ;;
                        esac
                      done
                      continue
                    fi
                    ;;
                esac
              fi

              norm=$arg
              while [[ $norm == *//* ]]; do
                norm=''${norm//\/\//\/}
              done
              while [[ $norm == */. || ( $norm != "/" && $norm == */ ) ]]; do
                norm=''${norm%/.}
                norm=''${norm%/}
                if [ -z "$norm" ]; then
                  norm="/"
                fi
              done
              if [ "$norm" = "/" ]; then
                echo "rm: it is dangerous to operate recursively on '/'" >&2
                exit 1
              fi

              if [ -n "$arg" ] && [[ $arg != /* ]]; then
                operands+=("./$arg")
              else
                operands+=("$arg")
              fi
            done

            if [ "''${#operands[@]}" -eq 0 ]; then
              if [ "$has_force" -eq 1 ]; then
                exit 0
              fi
              echo "usage: rm [-f | -i] [-dPRrvWx] file ..." >&2
              exit 1
            fi

            if [ "$has_force" -eq 1 ]; then
              options+=("-f")
            fi
            if [ "$has_verbose" -eq 1 ]; then
              options+=("-v")
            fi

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
              if declare -f "$_fn" >/dev/null 2>&1 && ! declare -f "_orig_$_fn" >/dev/null 2>&1; then
                eval "_orig_$_fn() $(declare -f "$_fn" | sed '1d')"
                eval "$_fn() { _orig_$_fn \"\$@\" && PATH_add \"${rmAsTrash}/bin\"; }"
              fi
            done
          '';
        }
      );
    };
}
