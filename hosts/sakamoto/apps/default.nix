# sakamoto 的业务容器：原先由 home-ops 的 docker compose 声明并部署，现在搬进本仓库
#
# 为什么仍然是 Compose 而不是 nix-darwin 的容器声明：macOS 侧没有 oci-containers 这类模块
# （vps-cc 用的是 NixOS 的 virtualisation.oci-containers），容器、命名卷与 homelab 网络都在
# OrbStack 里；换运行时等于把 10 个服务连数据一起再起一遍，与「把声明搬过来」是两件事。
#
# 这个目录管三件事：
# 1. compose.yaml 与 configs/：服务声明与静态配置；整目录进 Nix store，容器挂 store 路径
# 2. sops 模板：env 文件与 kopia 的云端仓库配置，激活时解密渲染，明文不进 store
# 3. launchd agent：GUI 登录（OrbStack 就绪）后拉起，之后每 15 分钟对账一次
#
# 切换、验收与回退步骤见同目录 README.md
{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  inherit (lib) genAttrs mkIf;

  # 与旧 Compose 相同的项目名。命名卷带项目名前缀（homelab-compose_kopia_cache），
  # 改名会新建两个空卷：kopia 需要重新对账，还会丢掉缓存
  projectName = "homelab-compose";

  # compose.yaml 与 configs/ 整目录进 store。compose.yaml 里的相对路径（./configs/...）
  # 按「compose 文件所在目录」解析，所以两者必须放在同一目录
  composeFile = "${./.}/compose.yaml";

  # sops 在激活时渲染出来的文件。env 与云端仓库配置含机密，只能由模板产生
  envFile = config.sops.templates."sakamoto-compose.env".path;
  kopiaMainRepositoryConfig = config.sops.templates."sakamoto-kopia-main-repository.config".path;

  # 键名即私有 secrets 仓库（sops/secrets/shelken/default.yaml）里的键。
  # 值沿用旧 Bitwarden 条目 compose-sakamoto 的字段，迁移时不要顺手轮换
  secretNames = [
    "compose-sakamoto/caddy-cloudflare-api-token"
    "compose-sakamoto/docker-data-dir"
    "compose-sakamoto/kopia-local-repo-password"
    "compose-sakamoto/kopia-main-password"
    "compose-sakamoto/kopia-webhook-url"
    "compose-sakamoto/local-repo-dir"
    "compose-sakamoto/main-domain"
    "compose-sakamoto/minio-data-dir"
    "compose-sakamoto/minio-root-password"
    "compose-sakamoto/minio-root-user"
    "compose-sakamoto/mirror-data-dir"
    "compose-sakamoto/openlist-webdav-password"
    "compose-sakamoto/openlist-webdav-username"
    "compose-sakamoto/sakamoto-data-dir"
  ];
  placeholder = name: config.sops.placeholder.${name};

  # 手动入口与 agent 共用同一份逻辑：agent 每 15 分钟跑一次 up，人工用同一个命令排障
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
      required_keys=(DOCKER_DATA_DIR MINIO_DATA_DIR MIRROR_DATA_DIR SAKAMOTO_DATA_DIR LOCAL_REPO_DIR)

      usage() {
        cat <<'USAGE'
      sakamoto-compose —— sakamoto 上 Compose 服务的统一入口

        up       等 OrbStack 与密钥就绪、检查数据目录，然后 docker compose up -d
        recreate 同上，但强制重建容器（改了 configs/ 里挂载的文件内容后用）
        status   容器状态
        logs     跟随日志
        check    只做语法与插值校验，不动容器

      launchd agent 每 15 分钟跑一次 up，日志在 ~/Library/Logs/sakamoto-compose.log
      USAGE
      }

      die() {
        printf 'sakamoto-compose: %s\n' "$*" >&2
        exit 1
      }

      # 登录瞬间 sops 渲染、OrbStack 守护进程与本 agent 谁先就绪不确定，都要等
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
        docker compose -f "$compose_file" --env-file "$env_file" -p "$project" "$@"
      }

      need_env() {
        wait_for 60 test -f "$env_file" ||
          die "没有 $env_file：确认 just hm 跑过、~/.config/sops/age/keys.txt 能解开密文"
      }

      running_count() {
        docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Names}}' | wc -l | tr -d ' '
      }

      preflight() {
        command -v docker >/dev/null 2>&1 ||
          die "PATH 里没有 docker：OrbStack 未装或命令行工具不在 /usr/local/bin"
        wait_for 120 docker info ||
          die "OrbStack 的 docker 守护进程 120 秒内没就绪"
        need_env

        # 外接盘没挂载时必须停手：bind mount 的源目录不存在时 Docker 会以 root 新建空目录，
        # 备份与镜像缓存会静默落到本地盘，事后很难分辨
        local key dir missing=""
        for key in "''${required_keys[@]}"; do
          dir=$(sed -n "s/^$key=//p" "$env_file" | head -n 1)
          [ -n "$dir" ] || die "env 文件里没有 $key"
          [ -d "$dir" ] || missing="$missing $key=$dir"
        done
        [ -z "$missing" ] || die "这些数据目录不存在，挂好外接盘再重试：$missing"
      }

      up() {
        local force=$1
        preflight

        local args=(up -d --remove-orphans)
        if [ "$force" = 1 ]; then
          args+=(--force-recreate)
        fi

        # 成功时输出很吵，只留失败的情况完整打出来
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

      # 变量名沿用旧 .env.tpl，compose.yaml 里的插值保持不变；
      # UID/GID 与通用 TZ 没有服务引用，不再复制过来
      sops.templates."sakamoto-compose.env" = {
        content = ''
          MAIN_DOMAIN=${placeholder "compose-sakamoto/main-domain"}
          DOCKER_DATA_DIR=${placeholder "compose-sakamoto/docker-data-dir"}
          MINIO_DATA_DIR=${placeholder "compose-sakamoto/minio-data-dir"}
          MIRROR_DATA_DIR=${placeholder "compose-sakamoto/mirror-data-dir"}
          MINIO_ROOT_USER=${placeholder "compose-sakamoto/minio-root-user"}
          MINIO_ROOT_PASSWORD=${placeholder "compose-sakamoto/minio-root-password"}
          CADDY_CLOUDFLARE_API_TOKEN=${placeholder "compose-sakamoto/caddy-cloudflare-api-token"}
          KOPIA_MAIN_PASSWORD=${placeholder "compose-sakamoto/kopia-main-password"}
          KOPIA_LOCAL_REPO_PASSWORD=${placeholder "compose-sakamoto/kopia-local-repo-password"}
          KOPIA_WEBHOOK_URL=${placeholder "compose-sakamoto/kopia-webhook-url"}
          SAKAMOTO_DATA_DIR=${placeholder "compose-sakamoto/sakamoto-data-dir"}
          LOCAL_REPO_DIR=${placeholder "compose-sakamoto/local-repo-dir"}
          KOPIA_MAIN_REPOSITORY_CONFIG=${kopiaMainRepositoryConfig}
        '';
      };

      # 云端仓库配置含 WebDAV 凭据。字段与旧 repository.config.tpl 一致：
      # 仓库路径 /dav/main、hostname 用容器名 sakamoto（策略按 shelken@sakamoto 找目标），改动会导致连不上旧库
      sops.templates."sakamoto-kopia-main-repository.config" = {
        content = ''
          {
            "storage": {
              "type": "webdav",
              "config": {
                "url": "https://drive.${placeholder "compose-sakamoto/main-domain"}/dav/main",
                "username": "${placeholder "compose-sakamoto/openlist-webdav-username"}",
                "password": "${placeholder "compose-sakamoto/openlist-webdav-password"}"
              }
            },
            "caching": {
              "cacheDirectory": "/app/cache",
              "maxCacheSize": 5242880000,
              "maxMetadataCacheSize": 5242880000,
              "maxListCacheDuration": 30
            }
          }
        '';
      };

      # 不写 domain：默认 gui，配 OrbStack 所在的 Aqua 会话；
      # 登录后 RunAtLoad 跑一次，StartInterval 负责补漏（开机时外接盘还没挂上、容器被手工删掉）；
      # plist 变化时 Home Manager 会重新加载，也会立刻再跑一次
      launchd.agents.sakamoto-compose = {
        enable = true;
        config = {
          Label = "space.ooooo.sakamoto-compose";
          ProgramArguments = [
            "${composeCli}/bin/sakamoto-compose"
            "up"
          ];
          RunAtLoad = true;
          KeepAlive = false;
          StartInterval = 900;
          # 轮换某个密钥的值时 plist 与 CLI 都没变化，RunAtLoad 不会触发；
          # 盯住渲染目录，sops 写完 env 就立刻对账，不用等下一次 StartInterval
          WatchPaths = [ (dirOf envFile) ];
          # launchd 的默认 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin，docker 在 /usr/local/bin
          EnvironmentVariables.PATH = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sakamoto-compose.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sakamoto-compose.err.log";
        };
      };

      home.packages = [ composeCli ];
    })
  ];
}
