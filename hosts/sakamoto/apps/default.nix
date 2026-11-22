{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    genAttrs
    mapAttrsToList
    mkIf
    ;

  projectName = "homelab-compose";

  # 传给 docker compose -f 的是固定路径的符号链接，不是 store 路径。
  # Compose 创建容器时把 -f 的路径写进标签（working_dir、config_files），OrbStack 按它分组；
  # 没被重建的容器保留旧标签，store 路径随内容变，每改一次 compose.yaml 就会多出一组。
  # 固定路径下标签不随内容变，只会有一组
  composeFile = "${config.xdg.configHome}/sakamoto-compose/compose.yaml";

  kopiaShared = ../../../modules/features/backup/kopia/server;

  configFiles = {
    CADDYFILE = ./configs/caddy/Caddyfile;
    MIRROR_CONFIG = ./configs/mirror-config.yaml;
    KOPIA_POLICY = kopiaShared + "/policy.json";
    KOPIA_ENTRYPOINT = kopiaShared + "/entrypoint.sh";
    KOPIA_LOCAL_REPOSITORY_CONFIG = ./configs/kopia/local/repository.config;
    KOPIA_LOCAL_POLICY = ./configs/kopia/local/policy.json;
  };
  configFileLines = concatStringsSep "\n" (
    mapAttrsToList (name: path: "${name}=${path}") configFiles
  );

  envFile = config.sops.templates."sakamoto-compose.env".path;

  secretNames = [
    "main-domain"
    "kopia/password"
    "kopia/webhook-url"
    "compose-sakamoto/cloudflare-api-token"
    "compose-sakamoto/data-dir"
    "compose-sakamoto/openlist-webdav-password"
    "compose-sakamoto/openlist-webdav-username"
    "compose-sakamoto/rustfs-password"
    "compose-sakamoto/rustfs-user"
  ];
  externalDisks = {
    sakamotoData = "/Volumes/sakamoto-data";
    localRepo = "/Volumes/BackUp3T/kopia-local-repo";
  };
  placeholder = name: config.sops.placeholder.${name};

  composeCli = pkgs.writeShellApplication {
    name = "sakamoto-compose";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
    ];
    text = ''
      compose_file=${composeFile}
      env_file=${envFile}
      project=${projectName}
      required_keys=(DOCKER_DATA_DIR SAKAMOTO_DATA_DIR LOCAL_REPO_DIR)

      usage() {
        cat <<'USAGE'
      sakamoto-compose —— sakamoto 上 Compose 服务的统一入口

        up       等密钥就绪、检查数据目录，通过后拉起 OrbStack、等它就绪，然后 docker compose up -d
        recreate 同上，但无条件重建全部容器（排障用；配置与密钥变化时 up 本身就会重建对应容器）
        status   容器状态
        logs     跟随日志
        check    只做语法与插值校验，不动容器

      launchd agent 在登录、外接盘挂载时与每 15 分钟各跑一次 up，日志在 ~/Library/Logs/sakamoto-compose.log
      USAGE
      }

      die() {
        printf 'sakamoto-compose: %s\n' "$*" >&2
        exit 1
      }

      wait_for() {
        local timeout=$1
        shift
        local waited=0
        while ! "$@" >/dev/null 2>&1; do
          if [ "$waited" -ge "$timeout" ]; then
            return 1
          fi
          sleep 5
          waited=$((waited + 5))
        done
      }

      compose() {
        docker compose -f "$compose_file" --env-file "$env_file" "$@"
      }

      need_env() {
        wait_for 60 test -f "$env_file" ||
          die "没有 $env_file：确认 just hm 跑过、~/.config/sops/age/keys.txt 能解开密文"
      }

      running_count() {
        docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' | wc -l | tr -d ' '
      }

      # 外接盘没挂载时必须停手：bind mount 的源目录不存在时 Docker 会以 root 新建空目录，
      # 备份与镜像缓存会静默落到本地盘，事后很难分辨
      check_data_dirs() {
        local key dir missing=""
        for key in "''${required_keys[@]}"; do
          dir=$(sed -n "s/^$key=//p" "$env_file" | head -n 1)
          [ -n "$dir" ] || die "env 文件里没有 $key"
          [ -d "$dir" ] || missing="$missing $key=$dir"
        done
        [ -z "$missing" ] || die "这些数据目录不存在，挂好外接盘再重试：$missing"
      }

      start_orbstack() {
        command -v docker >/dev/null 2>&1 ||
          die "PATH 里没有 docker：OrbStack 未装或命令行工具不在 /usr/local/bin"
        open -ga OrbStack || die "无法启动 OrbStack"
        wait_for 120 docker info ||
          die "OrbStack 的 docker 守护进程 120 秒内没就绪"
        orbctl config set app.start_at_login false ||
          echo "警告：关不掉 OrbStack 的「登录时启动」，盘没挂上时它可能自己启动" >&2
        if [ "$(orbctl config get memory_mib 2>/dev/null || true)" != "4096" ]; then
          if orbctl config set memory_mib 4096; then
            echo "提示：OrbStack 内存上限已设置为 4096 MiB，将在重启 OrbStack 后生效" >&2
          else
            echo "警告：无法设置 OrbStack 内存上限 memory_mib=4096" >&2
          fi
        fi
      }

      preflight() {
        need_env
        check_data_dirs
        start_orbstack
      }

      up() {
        local force=$1
        preflight

        local args=(up -d --remove-orphans)
        if [ "$force" = 1 ]; then
          args+=(--force-recreate)
        fi

        local output
        if ! output=$(compose "''${args[@]}" 2>&1); then
          printf '%s\n' "$output" >&2
          die "docker compose up 失败"
        fi
        printf '%s\n' "$output"
        printf 'ok: %s 个容器在运行\n' "$(running_count)"
      }

      case "''${1:-up}" in
        up) up 0 ;;
        recreate) up 1 ;;
        status)
          need_env
          compose ps
          ;;
        logs)
          need_env
          compose logs --tail=100 -f
          ;;
        check)
          need_env
          compose config --quiet && printf 'compose 配置解析通过\n'
          ;;
        -h | --help | help) usage ;;
        *)
          usage
          exit 2
          ;;
      esac
    '';
  };
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.shelken.secrets.enable;
          message = "sakamoto 的 Compose 服务需要主机启用 secrets (shelken.secrets.enable = true)：密钥由 sops 模板在激活时渲染";
        }
      ];
    }

    (mkIf config.shelken.secrets.enable {
      sops.secrets = genAttrs secretNames (_: mylib.mkDefaultSecret { });

      sops.templates."sakamoto-compose.env" = {
        content = ''
          MAIN_DOMAIN=${placeholder "main-domain"}
          DOCKER_DATA_DIR=${placeholder "compose-sakamoto/data-dir"}
          MINIO_ROOT_USER=${placeholder "compose-sakamoto/rustfs-user"}
          MINIO_ROOT_PASSWORD=${placeholder "compose-sakamoto/rustfs-password"}
          CADDY_CLOUDFLARE_API_TOKEN=${placeholder "compose-sakamoto/cloudflare-api-token"}
          KOPIA_PASSWORD=${placeholder "kopia/password"}
          KOPIA_WEBHOOK_URL=${placeholder "kopia/webhook-url"}
          OPENLIST_WEBDAV_USERNAME=${placeholder "compose-sakamoto/openlist-webdav-username"}
          OPENLIST_WEBDAV_PASSWORD=${placeholder "compose-sakamoto/openlist-webdav-password"}
          SAKAMOTO_DATA_DIR=${externalDisks.sakamotoData}
          LOCAL_REPO_DIR=${externalDisks.localRepo}
          ${configFileLines}
        '';
      };

      # 不写 domain：默认 gui，配 OrbStack 所在的 Aqua 会话；
      # 不用 WatchPaths：渲染目录在符号链接下面，sops 换代后 launchd 的监视时灵时不灵（实测三轮只触发一轮）；
      launchd.agents.sakamoto-compose = {
        enable = true;
        config = {
          Label = "space.ooooo.sakamoto-compose";
          ProgramArguments = [
            "${composeCli}/bin/sakamoto-compose"
            "up"
          ];
          RunAtLoad = true;
          StartOnMount = true;
          KeepAlive = false;
          StartInterval = 900;
          # launchd 的默认 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin，docker 在 /usr/local/bin；open 在 /usr/bin
          EnvironmentVariables.PATH = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sakamoto-compose.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sakamoto-compose.err.log";
        };
      };

      xdg.configFile."sakamoto-compose/compose.yaml".source = ./compose.yaml;

      home.packages = [ composeCli ];
    })
  ];
}
