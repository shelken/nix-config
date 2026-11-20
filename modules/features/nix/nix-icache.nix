# mise 下载失败不回退原站，所以规则只能跟开关走，不能写进 Home Manager 生成的 mise 配置。
# 也管 Homebrew：on 时写 ~/.config/homebrew/brew.env 与 ~/.homebrew/brew.env，把 ghcr.io 的 bottle 与 portable-ruby
# 经 HOMEBREW_ARTIFACT_DOMAIN 指到 icache/ghcr.io，并保留 HOMEBREW_DOCKER_REGISTRY_TOKEN=QQ== 让失败回退原站时仍带匿名认证。
# 同时写两处：交互 shell 设了 XDG_CONFIG_HOME 读前者，nix-darwin 激活跑 brew bundle 时未设它读后者；
# 状态 = ~/.config/nix/icache.conf 是否存在，靠用户级 nix.conf 的 `!include icache.conf` 生效
# （被包含文件不存在时 nix 静默忽略；用户级设置由客户端转发给 daemon，改文件即生效，不用重启）；
# 必须用覆盖语义的 `substituters`：nix 先按各源 nix-cache-info 里的 Priority 排序，同级才按列表顺序。
# icache 原样透传上游的 Priority，与原站同级，所以必须排在原站前面；`extra-substituters` 只会追加到末尾，
# 等于 icache 永不命中。列表不在这里重复维护 —— on 时现取系统列表拼在前面。
# 关闭 builders-use-substitutes：置 true 时 builder 自己去 substitute 输入，碰不到内网 icache；
# 置 false 则本机经 icache 取输入，再推给 builder。
# daemon 不重读系统 nix.conf，首次 switch 后用 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`
# 重启一次，之后 on/off 即时生效。root 跑的 nix（sudo / nixos-rebuild）读不到用户级配置，仍走系统列表。
{ config, ... }:
let
  icache = "https://icache.int.ooooo.space";
  brewArtifactDomain = "${icache}/ghcr.io";
  mirrors = [
    "${icache}/cache.nixos.org"
    "${icache}/nix-community.cachix.org"
  ];
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
