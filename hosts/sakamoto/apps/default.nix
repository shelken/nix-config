# sakamoto 的业务容器：原先由 home-ops 的 docker compose 声明并部署，现在搬进本仓库
#
# 为什么仍然是 Compose 而不是 nix-darwin 的容器声明：macOS 侧没有 oci-containers 这类模块
# （vps-cc 用的是 NixOS 的 virtualisation.oci-containers），容器、命名卷与 homelab 网络都在
# OrbStack 里；换运行时等于把 10 个服务连数据一起再起一遍，与「把声明搬过来」是两件事。
#
# 这个目录管三件事：
# 1. compose.yaml 与 configs/：服务声明与静态配置；每个文件单独进 Nix store，容器挂 store 路径
# 2. sops 模板：env 文件（口令、数据目录，以及上面各文件的 store 路径），激活时解密渲染，明文不进 store
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
  inherit (lib)
    concatStringsSep
    genAttrs
    mapAttrsToList
    mkIf
    ;

  # 与旧 Compose 相同的项目名。命名卷带项目名前缀（homelab-compose_kopia_cache），
  # 改名会新建两个空卷：kopia 需要重新对账，还会丢掉缓存
  projectName = "homelab-compose";

  # 传给 docker compose -f 的是固定路径的符号链接，不是 store 路径。
  # Compose 创建容器时把 -f 的路径写进标签（working_dir、config_files），OrbStack 按它分组；
  # 没被重建的容器保留旧标签，store 路径随内容变，每改一次 compose.yaml 就会多出一组。
  # 固定路径下标签不随内容变，只会有一组
  composeFile = "${config.xdg.configHome}/sakamoto-compose/compose.yaml";

  # 容器要读的静态配置，键名即 compose.yaml 里 volumes 引用的变量。
  # 必须是 volumes 而不是 configs:：Compose 的服务 hash 不含 configs 的路径与内容，改了配置 up 不会重建容器；
  # volumes 的源路径在 hash 里，每个文件单独进 store、路径随内容变，所以改哪个文件只重建用到它的服务
  # 与 vps-cc 共用的 kopia 入口脚本与策略
  kopiaShared = ../../../modules/features/backup/_kopia-server;

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

  # sops 在激活时渲染出来的 env 文件，含机密，只能由模板产生
  envFile = config.sops.templates."sakamoto-compose.env".path;

  # 键名即私有 secrets 仓库（sops/secrets/shelken/default.yaml）里的键。
  # 前三项是跨主机共用的键（域名、kopia 口令与 webhook），其余在 compose-sakamoto/ 下；
  # 值沿用旧 Bitwarden 条目 compose-sakamoto 的字段，迁移时不要顺手轮换
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
  # 外接盘上的两个固定路径，与旧 compose 里写死的一致；不是机密，不进 sops。
  # 写在 env 里而不是 compose.yaml：开机检查要读同一份来确认盘已挂载
  externalDisks = {
    sakamotoData = "/Volumes/sakamoto-data";
    localRepo = "/Volumes/BackUp3T/kopia-local-repo";
  };
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
      required_keys=(DOCKER_DATA_DIR SAKAMOTO_DATA_DIR LOCAL_REPO_DIR)

      usage() {
        cat <<'USAGE'
      sakamoto-compose —— sakamoto 上 Compose 服务的统一入口

        up       等 OrbStack 与密钥就绪、检查数据目录，然后 docker compose up -d
        recreate 同上，但无条件重建全部容器（排障用；配置与密钥变化时 up 本身就会重建对应容器）
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
        docker compose -f "$compose_file" --env-file "$env_file" "$@"
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
      # 登录后 RunAtLoad 跑一次，StartInterval 负责补漏（开机时外接盘还没挂上、容器被手工删掉），
      # 也是密钥值轮换后的收敛路径：env 变了，下一轮 up 会重建受影响的容器。
      # 不用 WatchPaths：渲染目录在符号链接下面，sops 换代后 launchd 的监视时灵时不灵（实测三轮只触发一轮）；
      # compose.yaml、配置文件或密钥变了时 plist 都不变，等下一轮，或手动 sakamoto-compose up；
      # 只有 default.nix 里 CLI 本身变了，plist 才跟着变，Home Manager 会重新加载并立刻再跑一次
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
          # launchd 的默认 PATH 只有 /usr/bin:/bin:/usr/sbin:/sbin，docker 在 /usr/local/bin
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
