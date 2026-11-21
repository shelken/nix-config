{ config, ... }:
let
  icache = "https://icache.int.ooooo.space";
  brewArtifactDomain = "${icache}/ghcr.io";
  mirrors = [
    "${icache}/cache.nixos.org"
    "${icache}/nix-community.cachix.org"
  ];
  # 只改写 releases/download：icache 只放行这一类，latest 等会变的地址它会拒绝，必须留给原站
  miseUrlReplacements = {
    "regex:^https://github\\.com/([^/]+)/([^/]+)/releases/download/(.+)" =
      "${icache}/github.com/$1/$2/releases/download/$3";
  };
in
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-icache ];

  flake.modules.homeManager.nix-icache =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      miseConf = "${config.home.homeDirectory}/.config/mise/conf.d/icache.toml";
      miseConfSource = (pkgs.formats.toml { }).generate "mise-icache.toml" {
        settings.url_replacements = miseUrlReplacements;
      };
      brewEnvHeader = "# 由 nix-icache 生成";
      brewEnvSource = pkgs.writeText "homebrew-icache.env" ''
        ${brewEnvHeader}
        HOMEBREW_ARTIFACT_DOMAIN=${brewArtifactDomain}
        # 只设 ARTIFACT_DOMAIN 时 Homebrew 会省略 Authorization，回退官方 ghcr.io 会 401，必须保留公开匿名 token
        HOMEBREW_DOCKER_REGISTRY_TOKEN=QQ==
      '';
      nix-icache = pkgs.writeShellApplication {
        name = "nix-icache";
        # install -D 是 GNU 语义；SSH 非交互登录的 PATH 只有系统路径，会用到 macOS 的 BSD install
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          conf="$HOME/.config/nix/icache.conf"
          miseConf="$HOME/.config/mise/conf.d/icache.toml"
          brewXdgEnv="$HOME/.config/homebrew/brew.env"
          brewHomeEnv="$HOME/.homebrew/brew.env"
          mirrors="${lib.concatStringsSep " " mirrors}"

          # 非交互 SSH 等精简 PATH 环境不含 /nix/var/nix/profiles/default/bin，需回退到默认路径
          systemSubstituters() {
            local nixBin=""
            nixBin=$(command -v nix || true)
            if [ -z "$nixBin" ] && [ -x /nix/var/nix/profiles/default/bin/nix ]; then
              nixBin=/nix/var/nix/profiles/default/bin/nix
            fi
            if [ -z "$nixBin" ]; then
              return 1
            fi
            NIX_CONFIG="" NIX_USER_CONF_FILES=${pkgs.emptyFile} "$nixBin" config show substituters
          }

          isManagedBrewEnv() {
            local first_line=""
            [ ! -L "$1" ] && [ -f "$1" ] && [ -r "$1" ] && IFS= read -r first_line < "$1" && [ "$first_line" = "${brewEnvHeader}" ]
          }

          case "''${1:-status}" in
            on)
              for f in "$brewXdgEnv" "$brewHomeEnv"; do
                if { [ -e "$f" ] || [ -L "$f" ]; } && ! isManagedBrewEnv "$f"; then
                  echo "nix-icache: $f 不是由 nix-icache 生成，未改动任何配置" >&2
                  exit 1
                fi
              done
              if ! system=$(systemSubstituters) || [ -z "$system" ]; then
                echo "nix-icache: 读不到系统 substituters，未改动 $conf" >&2
                exit 1
              fi
              mkdir -p "$(dirname "$conf")"
              {
                echo "# 由 nix-icache 生成"
                echo "substituters = $mirrors $system"
                echo "builders-use-substitutes = false"
              } > "$conf.tmp"
              mv "$conf.tmp" "$conf"
              install -D -m 0644 ${miseConfSource} "$miseConf"
              install -D -m 0644 ${brewEnvSource} "$brewXdgEnv"
              install -D -m 0644 ${brewEnvSource} "$brewHomeEnv"
              echo "icache: on"
              ;;
            off)
              rm -f "$conf" "$miseConf"
              for f in "$brewXdgEnv" "$brewHomeEnv"; do
                if isManagedBrewEnv "$f"; then
                  rm -f "$f"
                elif [ -e "$f" ] || [ -L "$f" ]; then
                  echo "nix-icache: 保留非受管文件 $f" >&2
                fi
              done
              echo "icache: off"
              ;;
            status)
              if [ -e "$conf" ]; then echo on; else echo off; fi
              ;;
            *)
              echo "用法: nix-icache [on|off|status]" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      options.shelken.nix.icache.miseConfigFile = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = miseConf;
        description = "开关打开时存在的 mise 下载改写配置；沙箱的 sb 每次进入 VM 前读它";
      };

      config = {
        home.packages = [ nix-icache ];
        home.file.".config/nix/nix.conf".text = lib.mkAfter "!include icache.conf";

        home.activation.nixIcacheSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          _nix_icache_state=$(${nix-icache}/bin/nix-icache status)
          if ! run ${nix-icache}/bin/nix-icache "$_nix_icache_state"; then
            echo "nix-icache: 部署自动同步($_nix_icache_state)失败，请排查上方错误后手动执行 nix-icache $_nix_icache_state" >&2
          fi
        '';
      };
    };

  flake.modules.nixos.nix-icache-system =
    { lib, ... }:
    {
      nix.settings = {
        substituters = lib.mkBefore mirrors;
        connect-timeout = 2;
      };
    };
}
