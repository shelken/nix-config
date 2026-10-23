#!/usr/bin/env bash
# ==============================================================================
# Agent 沙箱端到端验证脚手架 (E2E Test Harness)
#
# 职责说明:
#   本脚本为 Agent 沙箱重构（Issue #126 / #127）提供端到端测试脚手架。
#   为后续单元 2-5 提供独立、可复用、异常安全的一次性主 VM、隔离 MSB_HOME、
#   假项目目录与网络/命令断言原语。
#
# 架构与硬约束原则:
#   1. 日常 VM 零污染: 绝对不触碰日常 VM `sb-default`（不 stop/rm/modify/重建）。
#   2. 环境变量隔离: 绝不全局 `export MSB_HOME`，所有 msb 命令仅通过单命令前缀
#      `MSB_CONFIG_PATH=... MSB_HOME=... msb ...` 执行，避免污染持久 shell。
#   3. 符号链接穿透: msb 挂载宿主路径强制通过 `realpath` 解析真实物理路径（macOS 下
#      `/tmp` 为指向 `/private/tmp` 的符号链接，直接挂载会导致 msb 拒绝）。
#   4. 复制父目录预建: `msb copy` 不会自动递归创建 guest 端父目录；本脚本的
#      `harness_copy` 预先在 guest 内执行 `mkdir -p`，规避 open os error 2。
#   5. 网络断言基于应用层: msb 本地网络栈会伪先响应 TCP 握手，禁止使用 ICMP ping
#      或 `/dev/tcp` 判定通断；统一以应用层 HTTP 响应（HTTP 状态码及文本匹配）断言。
#   6. 资源异常自愈: 统一由 trap 钩子捕获 EXIT / INT / TERM / HUP，无论测试成功还是
#      异常断言失败，自动清理 VM、volume、残留后台进程与临时目录。
#   7. 密钥零泄露: 假凭据与假 secret 仅使用纯占位假值，严禁读取系统真实密钥。
#
# 原语函数清单 (可由后续单元测试脚本 source 导入):
#   - harness_setup [work_dir]
#       初始化独立临时测试根目录、MSB_HOME 及 microsandbox-config.json；
#       自动挂载 EXIT/INT/TERM trap 进行资源兜底清理。
#   - harness_cleanup
#       停止并删除当前临时 MSB_HOME 内的所有 VM、删除 volume、终止残留进程、
#       并删除临时根目录。
#   - harness_msb <args...>
#       在当前独立 MSB_HOME 环境中执行 msb 命令，不污染当前 shell 环境变量。
#   - harness_create_vm [vm_name] [msb_create_args...]
#       创建并启动一次性 VM，等待其进入 Running 状态。支持自定义 --conf 或参数。
#   - harness_exec <vm_name> <cmd...>
#       在 VM 内流式执行命令，原样透传标准输出与返回码。
#   - harness_exec_capture <vm_name> <cmd...>
#       在 VM 内执行命令并捕获标准输出，原样透传返回码。
#   - harness_copy <vm_name> <host_src> <guest_dst>
#       解析宿主真实路径，并在 guest 内自动创建父目录后复制文件。
#   - harness_setup_fake_workspace
#       在临时目录下建立假工作区（包含相邻项目 project-a、project-b、worktree、
#       假凭据假 secret），供隔离性与权限边界测试使用。
#   - harness_assert_http <vm_name> <url> [expected_substring] [timeout]
#       断言 VM 内通过 HTTP 发起请求成功且内容符合预期。
#   - harness_assert_http_blocked <vm_name> <url> [timeout]
#       断言 VM 内发往未授权目标的 HTTP 请求被拦截（超时或连接重置）。
#   - harness_verify_clean [vm_name]
#       检查临时 VM 进程已退出、临时目录已删除，且宿主日常 `sb-default` 未受干扰。
#   - harness_find_or_build_app <override_var> <bin-name>
#       只构建一次 Home Manager activationPackage，再在产物里定位指定命令（sb / omp-sb）。
#   - harness_self_test
#       执行单元 0 的自测验收流程（创建 -> 执行 -> 验证坑点 -> 销毁 -> 零残留验证）。
#
# 子命令调用用法 (直接执行):
#   ./harness.sh [self-test]     # 运行单元 0 端到端完整自测
#   ./harness.sh setup           # 仅建立临时测试环境并输出路径变量
#   ./harness.sh cleanup <dir>   # 清理指定的测试目录
# ==============================================================================

set -euo pipefail

# 全局环境标识
E2E_DIR=""
E2E_MSB_HOME=""
E2E_MSB_CONFIG=""
E2E_WORKSPACE=""
E2E_VM_NAME="e2e-vm-$$"
MSB_BIN=""
# Home Manager activationPackage 产物目录（首次 nix build 后缓存，避免重复构建）
E2E_APP_DIR=""
_HARNESS_TRAP_ACTIVE=0

# ------------------------------------------------------------------------------
# 辅助函数: 定位 msb 二进制及校验版本
# ------------------------------------------------------------------------------
harness_find_msb() {
  if [[ -n "$MSB_BIN" && -x "$MSB_BIN" ]]; then
    return 0
  fi

  if command -v mise >/dev/null 2>&1 && mise which msb >/dev/null 2>&1; then
    MSB_BIN="$(mise which msb)"
  elif command -v msb >/dev/null 2>&1; then
    MSB_BIN="$(command -v msb)"
  else
    echo "[-] 错误: 未在 PATH 或 mise 中找到 msb 可执行文件" >&2
    return 1
  fi

  local version
  version="$("$MSB_BIN" --version 2>&1 || true)"
  if [[ "$version" != *"0.7.7"* ]]; then
    echo "[!] 警告: msb 版本不是 0.7.7 (当前: $version)，请注意兼容性" >&2
  fi
}

# ------------------------------------------------------------------------------
# 辅助函数: 定位 Home Manager 产物里的命令（构建只做一次，结果缓存在 E2E_APP_DIR）
#   $1 覆盖用环境变量名（如 SB_BIN），其值可执行时直接返回
#   $2 产物内的命令名（如 sb / omp-sb）
# 单次 nix build 的产物目录会缓存到 E2E_APP_DIR，后续调用直接复用。
# ------------------------------------------------------------------------------
harness_find_or_build_app() {
  local override_var="$1"
  local bin_name="$2"
  local override_value="${!override_var:-}"
  if [[ -n "$override_value" && -x "$override_value" ]]; then
    echo "$override_value"
    return 0
  fi

  if [[ -z "$E2E_APP_DIR" ]]; then
    E2E_APP_DIR="$(nix build --no-link --print-out-paths \
      '.#homeConfigurations.mio.config.home.activationPackage' 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "$E2E_APP_DIR" && -x "$E2E_APP_DIR/home-path/bin/$bin_name" ]]; then
    readlink -f "$E2E_APP_DIR/home-path/bin/$bin_name"
    return 0
  fi

  echo "[-] 错误: 无法构建或定位 $bin_name 二进制 (可设置 $override_var 覆盖)" >&2
  return 1
}

# ------------------------------------------------------------------------------
# 辅助函数: 把沙箱配置发布到指定目录（不改动宿主 ~/.config/sandbox）
#   $1 发布目录（脚本把内容写到 <dir>/current）
# 构建期产物里的 guest 环境与 sync 脚本都靠它进入 guest；
# 没有它，VM 就没有 /run/sandbox-config/current（无工具声明，也就无环境）。
# ------------------------------------------------------------------------------
harness_publish_config() {
  local dst="$1"
  local repo_root publish_script
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd -P)"
  mkdir -p "$dst"

  publish_script="$(nix eval --impure --raw --expr "
    let f = builtins.getFlake \"$repo_root\"; in
    builtins.toString f.homeConfigurations.mio.config.home.activation.sandboxPublishConfig.data" 2>/dev/null | sed 's/^run //')"
  if [[ ! -x "$publish_script" ]]; then
    echo "[-] 错误: 找不到配置发布脚本: $publish_script" >&2
    return 1
  fi

  SANDBOX_CONFIG_DIR="$dst" "$publish_script"
  if [[ ! -f "$dst/current/guest-env.sh" ]]; then
    echo "[-] 错误: 发布目录缺少 guest-env.sh: $dst/current" >&2
    return 1
  fi
}

# ------------------------------------------------------------------------------
# 辅助函数: 解析绝对真实路径 (去掉所有符号链接)
# ------------------------------------------------------------------------------
harness_resolve_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target" 2>/dev/null && return 0
  fi
  if [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
  elif [[ -f "$target" ]]; then
    local dir base
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    echo "$(cd "$dir" && pwd -P)/$base"
  else
    echo "$target"
  fi
}

# ------------------------------------------------------------------------------
# 原语: 初始化独立测试环境
# ------------------------------------------------------------------------------
harness_setup() {
  harness_find_msb

  local custom_dir="${1:-}"
  if [[ -n "$custom_dir" ]]; then
    mkdir -p "$custom_dir"
    E2E_DIR="$(harness_resolve_path "$custom_dir")"
  else
    local tmp_raw
    tmp_raw="$(mktemp -d /tmp/msb-e2e-XXXXXX)"
    E2E_DIR="$(harness_resolve_path "$tmp_raw")"
  fi

  E2E_MSB_HOME="$E2E_DIR/msb-home"
  E2E_MSB_CONFIG="$E2E_DIR/microsandbox-config.json"
  mkdir -p "$E2E_MSB_HOME"

  # 宿主共用 mise 目录（ADR 0004 / 任务硬约束）：一次性 VM 也挂真实共用目录，
  # 保证整个任务期间每种工具最多完整下载一次；清理绝不删除该目录。
  # 可用 SB_MISE_HOST_DIR 覆盖（默认指向任务规定路径），始终 realpath。
  E2E_MISE_HOST_DIR="${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"
  mkdir -p "$E2E_MISE_HOST_DIR/data" "$E2E_MISE_HOST_DIR/cache" 2>/dev/null || true
  E2E_MISE_HOST_DIR="$(harness_resolve_path "$E2E_MISE_HOST_DIR")"
  export SB_MISE_HOST_DIR="$E2E_MISE_HOST_DIR"

  # 获取宿主镜像缓存真实路径 (共享已缓存的 ubuntu 镜像，避免重新下载)
  local host_cache
  host_cache="${HOME}/.cache/microsandbox"
  if [[ -d "$host_cache" ]]; then
    host_cache="$(harness_resolve_path "$host_cache")"
  fi

  # 写入 microsandbox 全局配置: 关闭 metrics 采样，复用 host 缓存
  cat <<EOF > "$E2E_MSB_CONFIG"
{
  "version": 1,
  "home": "$E2E_MSB_HOME",
  "paths": {
    "cache": "$host_cache"
  },
  "sandbox_defaults": {
    "metrics_sample_interval_ms": 0,
    "disable_metrics_sample": true
  }
}
EOF

  # 挂载 trap 保证异常与退出时自动清理
  if [[ "$_HARNESS_TRAP_ACTIVE" -eq 0 ]]; then
    trap 'harness_cleanup' EXIT INT TERM HUP
    _HARNESS_TRAP_ACTIVE=1
  fi

  echo "[+] 独立测试环境已就绪: E2E_DIR=$E2E_DIR"
}

# ------------------------------------------------------------------------------
# 原语: 独立环境执行 msb (绝不污染外层环境变量)
# ------------------------------------------------------------------------------
harness_msb() {
  harness_find_msb
  if [[ -z "$E2E_DIR" || -z "$E2E_MSB_CONFIG" || -z "$E2E_MSB_HOME" ]]; then
    echo "[-] 错误: harness 尚未初始化，请先调用 harness_setup" >&2
    return 1
  fi
  MSB_CONFIG_PATH="$E2E_MSB_CONFIG" MSB_HOME="$E2E_MSB_HOME" "$MSB_BIN" "$@"
}

# ------------------------------------------------------------------------------
# 辅助: 生成带共用 mise 挂载的一次性 VM conf (ADR 0004)
#   宿主 E2E_MISE_HOST_DIR (真实路径) → guest /opt/sandbox-mise:rw
#   与 sb generate_msb_config 的注入方式一致 (SB_MISE_HOST_DIR 变量驱动)
# ------------------------------------------------------------------------------
harness_write_vm_conf() {
  local conf_file="$1"
  local mise_host="$E2E_MISE_HOST_DIR"
  jq -n \
    --arg mise "$mise_host:/opt/sandbox-mise:rw" \
    '{
      image: "ubuntu",
      cpus: 2,
      memory: "2G",
      mounts: [ $mise ]
    }' > "$conf_file"
}

# ------------------------------------------------------------------------------
# 原语: 创建并启动一次性 VM
# ------------------------------------------------------------------------------
harness_create_vm() {
  local vm_name="${1:-$E2E_VM_NAME}"
  shift || true

  echo "[+] 正在创建一次性测试 VM: $vm_name"
  if [[ $# -eq 0 ]]; then
    # 默认创建带共用 mise 挂载的 Ubuntu VM（ADR 0004）；使用 --pull never 保证不发起外网镜像下载
    local auto_conf="$E2E_DIR/${vm_name}.conf.json"
    harness_write_vm_conf "$auto_conf"
    harness_msb create --name "$vm_name" --conf "$auto_conf" --pull never
  else
    harness_msb create --name "$vm_name" "$@"
  fi

  # 等待 VM 达到 Running 状态
  local max_attempts=30
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    local status
    status="$(harness_msb inspect "$vm_name" --format json 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true)"
    if [[ "$status" == "Running" || "$status" == "running" ]]; then
      echo "[+] VM $vm_name 已成功进入 Running 状态"
      return 0
    fi
    sleep 0.5
    ((attempt++))
  done

  echo "[-] 错误: 等待 VM $vm_name 启动超时" >&2
  return 1
}

# ------------------------------------------------------------------------------
# 原语: 在 VM 内执行命令 (流式输出并透传状态码)
# ------------------------------------------------------------------------------
harness_exec() {
  local vm_name="$1"
  shift
  harness_msb exec "$vm_name" --stream -- "$@"
}

# ------------------------------------------------------------------------------
# 原语: 在 VM 内执行命令并捕获标准输出
# ------------------------------------------------------------------------------
harness_exec_capture() {
  local vm_name="$1"
  shift
  harness_msb exec "$vm_name" -- "$@"
}

# ------------------------------------------------------------------------------
# 原语: 安全复制文件至 VM (解决 msb copy 不建父目录问题)
# ------------------------------------------------------------------------------
harness_copy() {
  local vm_name="$1"
  local host_src="$2"
  local guest_dst="$3"

  local real_src
  real_src="$(harness_resolve_path "$host_src")"
  if [[ ! -e "$real_src" ]]; then
    echo "[-] 错误: 宿主源文件不存在: $host_src (解析为: $real_src)" >&2
    return 1
  fi

  # 在 guest 内先创建父目录（非流式，避免与并发上下文争用 --stream）
  local guest_parent
  guest_parent="$(dirname "$guest_dst")"
  harness_exec_capture "$vm_name" mkdir -p "$guest_parent" >/dev/null

  # 执行复制
  harness_msb copy "$real_src" "${vm_name}:${guest_dst}"
}

# ------------------------------------------------------------------------------
# 原语: 准备假项目环境 (相邻项目、worktree、假凭据、假 secret)
# ------------------------------------------------------------------------------
harness_setup_fake_workspace() {
  if [[ -z "$E2E_DIR" ]]; then
    echo "[-] 错误: 请先调用 harness_setup" >&2
    return 1
  fi

  E2E_WORKSPACE="$E2E_DIR/workspace"
  mkdir -p "$E2E_WORKSPACE"
  E2E_WORKSPACE="$(harness_resolve_path "$E2E_WORKSPACE")"

  local proj_a="$E2E_WORKSPACE/project-a"
  local proj_b="$E2E_WORKSPACE/project-b"
  local shared_dir="$E2E_WORKSPACE/shared-extra"
  local creds_dir="$E2E_WORKSPACE/fake-credentials"

  mkdir -p "$proj_a" "$proj_b" "$shared_dir" "$creds_dir"

  # 1. 初始化项目 A (目标测试项目)
  (
    cd "$proj_a"
    git init -q
    echo "# Project A Main Repo" > README.md
    echo "console.log('Project A App');" > index.js
    cat <<'YAML' > .sandbox.yaml
# 测试用项目沙箱配置
imports:
  - src: ../fake-credentials/fake-token.json
    dst: fake-token.json
network:
  - "127.0.0.1"
paths:
  - ../shared-extra
YAML
    git -c user.name="E2ETest" -c user.email="e2e@test.local" add .
    git -c user.name="E2ETest" -c user.email="e2e@test.local" commit -m "initial commit in proj A" -q
    git branch feature-branch
    git worktree add "$E2E_WORKSPACE/project-a-worktree" feature-branch -q
  )

  # 2. 初始化项目 B (相邻不可见测试项目)
  (
    cd "$proj_b"
    git init -q
    echo "# Project B - Adjacent Private Project" > README.md
    echo "SUPER_SENSITIVE_DATA_DO_NOT_EXPOSE" > private-secret.txt
    git -c user.name="E2ETest" -c user.email="e2e@test.local" add .
    git -c user.name="E2ETest" -c user.email="e2e@test.local" commit -m "initial commit in proj B" -q
  )

  # 3. 准备共享路径与假凭据 (纯测试假值，绝不含真实 secret)
  echo "shared-extra-content-12345" > "$shared_dir/shared-file.txt"
  cat <<'JSON' > "$creds_dir/fake-token.json"
{
  "auth_type": "bearer",
  "access_token": "dummy_mock_access_token_for_e2e_test",
  "account_id": "test-account-123"
}
JSON

  # 4. 导出模拟假 Secret 环境变量
  export E2E_MOCK_SECRET_NAME="MOCK_AUTH_SECRET"
  export E2E_MOCK_SECRET_VALUE="mock_secret_value_for_sandbox_test_7788"

  echo "[+] 假工作区已就绪: $E2E_WORKSPACE"
  echo "    - 目标项目: $proj_a"
  echo "    - 目标项目 worktree: $E2E_WORKSPACE/project-a-worktree"
  echo "    - 相邻项目: $proj_b"
  echo "    - 共享额外路径: $shared_dir"
  echo "    - 假凭据文件: $creds_dir/fake-token.json"
}

# ------------------------------------------------------------------------------
# 原语: 网络断言 - 应用层 HTTP 成功断言
# ------------------------------------------------------------------------------
harness_assert_http() {
  local vm_name="$1"
  local url="$2"
  local expected="${3:-}"
  local timeout="${4:-5}"

  # 优先检测 curl，若无则使用 Ubuntu 内置的 perl
  local probe_cmd
  probe_cmd=$(cat <<EOF
if command -v curl >/dev/null 2>&1; then
  curl -s -S -f -m $timeout "$url"
elif [[ -x /nix/store/*curl*/bin/curl ]]; then
  /nix/store/*curl*/bin/curl -s -S -f -m $timeout "$url"
else
  perl -e '
    use IO::Socket::INET;
    my \$url = "$url";
    \$url =~ m{^https?://([^/:]+)(?::(\d+))?(.*)\$};
    my \$host = \$1;
    my \$port = \$2 || 80;
    my \$path = \$3 || "/";
    my \$sock = IO::Socket::INET->new(PeerAddr => \$host, PeerPort => \$port, Proto => "tcp", Timeout => $timeout)
      or exit 1;
    print \$sock "GET \$path HTTP/1.1\r\nHost: \$host\r\nConnection: close\r\n\r\n";
    my \$resp = "";
    while (my \$line = <\$sock>) { \$resp .= \$line; }
    close(\$sock);
    if (\$resp =~ m{HTTP/\d\.\d\s+([23]\d\d)}) {
      print \$resp;
      exit 0;
    }
    exit 2;
  '
fi
EOF
)

  local output
  if ! output="$(harness_exec "$vm_name" bash -c "$probe_cmd")"; then
    echo "[-] HTTP 请求失败或返回非 2xx/3xx: $url" >&2
    return 1
  fi

  if [[ -n "$expected" ]]; then
    if ! grep -q "$expected" <<< "$output"; then
      echo "[-] HTTP 响应内容不符合预期 (未找到 '$expected'):" >&2
      echo "$output" >&2
      return 1
    fi
  fi
  return 0
}

# ------------------------------------------------------------------------------
# 原语: 网络断言 - 应用层 HTTP 拦截断言 (要求必须超时或连接失败)
# ------------------------------------------------------------------------------
harness_assert_http_blocked() {
  local vm_name="$1"
  local url="$2"
  local timeout="${3:-3}"

  # 说明: 由于 msb 本地网络代理会先行响应 TCP 握手，单纯 TCP 连接成功不代表放行。
  # 必须以是否收到应用层 HTTP 响应行作为判别准则:
  # - 若收到合法 HTTP 响应 (状态码)，说明网络未被拦截 (失败)；
  # - 若读响应超时、返回空或连接失败，说明被拦截 (成功)。
  local probe_cmd
  probe_cmd=$(cat <<EOF
if command -v curl >/dev/null 2>&1; then
  curl -s -f -m $timeout "$url" >/dev/null 2>&1
elif [[ -x /nix/store/*curl*/bin/curl ]]; then
  /nix/store/*curl*/bin/curl -s -f -m $timeout "$url" >/dev/null 2>&1
else
  perl -e '
    use IO::Socket::INET;
    my \$url = "$url";
    \$url =~ m{^https?://([^/:]+)(?::(\d+))?(.*)\$};
    my \$host = \$1;
    my \$port = \$2 || 80;
    my \$path = \$3 || "/";
    my \$sock = IO::Socket::INET->new(PeerAddr => \$host, PeerPort => \$port, Proto => "tcp", Timeout => $timeout);
    if (!\$sock) {
      # 连 TCP 握手都未建立 (被拒绝)
      exit 1;
    }
    print \$sock "GET \$path HTTP/1.1\r\nHost: \$host\r\nConnection: close\r\n\r\n";
    my \$line = <\$sock>;
    close(\$sock);
    if (defined \$line && \$line =~ m{^HTTP/\d\.\d\s+\d{3}}) {
      # 实际收到了 HTTP 响应行，说明目标可达未被拦截
      exit 0;
    }
    # 读超时或连接被对端切断，未收到应用层响应 -> 判定为被拦截
    exit 1;
  '
fi
EOF
)

  if harness_exec "$vm_name" bash -c "$probe_cmd" >/dev/null 2>&1; then
    echo "[-] 预期网络被拦截，但实际请求成功收到应用层响应: $url" >&2
    return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# 原语: 清理测试资源与目录 (幂等安全清理)
# ------------------------------------------------------------------------------
harness_cleanup() {
  local exit_code=$?
  # 避免递归触发 trap
  trap - EXIT INT TERM HUP
  _HARNESS_TRAP_ACTIVE=0

  if [[ -n "$E2E_DIR" && -d "$E2E_DIR" ]]; then
    echo "[*] 开始清理测试资源: $E2E_DIR"

    # 1. 尝试停止并删除当前 MSB_HOME 内的所有沙箱
    if [[ -n "$E2E_MSB_CONFIG" && -f "$E2E_MSB_CONFIG" && -n "$MSB_BIN" && -x "$MSB_BIN" ]]; then
      local sandboxes
      sandboxes="$(harness_msb ls --format json 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)"
      if [[ -n "$sandboxes" ]]; then
        for sb in $sandboxes; do
          echo "    - 停止并删除沙箱: $sb"
          harness_msb stop "$sb" >/dev/null 2>&1 || true
          harness_msb rm --force "$sb" >/dev/null 2>&1 || true
        done
      fi

      # 2. 清理 volume
      local volumes
      volumes="$(harness_msb volume ls --format json 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)"
      if [[ -n "$volumes" ]]; then
        for vol in $volumes; do
          echo "    - 删除 volume: $vol"
          harness_msb volume rm "$vol" >/dev/null 2>&1 || true
        done
      fi

      # 3. 验证当前 MSB_HOME 内已无沙箱残留
      local remaining_sb
      remaining_sb="$(harness_msb ls --format json 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)"
      if [[ -n "$remaining_sb" ]]; then
        echo "[!] 警告: 仍有未删除沙箱: $remaining_sb" >&2
      else
        echo "    - 确认临时 MSB_HOME 内沙箱列表已清空 (msb ls 无残留)"
      fi
    fi

    # 4. 终止名字含本测试临时 VM 名的残留 machine 进程（按 VM 名定向）
    # kill -9 逐个 PID 执行：拼成一个含空格的字符串会让 kill 收到单个无效参数
    local lingering_pids pid
    lingering_pids="$(pgrep -f "msb machine.*$E2E_VM_NAME" 2>/dev/null || true)"
    if [[ -n "${lingering_pids// /}" ]]; then
      echo "    - 发现残留进程 ($(echo "$lingering_pids" | tr '\n' ' '))，正在强制终止..."
      for pid in $lingering_pids; do
        kill -9 "$pid" 2>/dev/null || true
      done
    fi

    # 5. 删除临时工作目录
    rm -r "$E2E_DIR" 2>/dev/null || true
    echo "[+] 测试资源清理完毕"
  fi

  return "$exit_code"
}

# ------------------------------------------------------------------------------
# 原语: 验证清理彻底性与宿主日常 VM 未受干扰
# 残留检查: 按本测试的 VM 名与后台 PID 定向检查，不依赖 lsof 文件句柄扫描。
# ------------------------------------------------------------------------------
harness_verify_clean() {
  local vm_name="${1:-$E2E_VM_NAME}"

  echo "[+] 正在验证清理彻底性..."

  # 1. 临时目录必须已被删除
  if [[ -n "$E2E_DIR" && -d "$E2E_DIR" ]]; then
    echo "[-] 错误: 临时测试目录仍存在: $E2E_DIR" >&2
    return 1
  fi
  echo "    - 临时目录已确认删除"

  # 2. 测试 VM 不应仍有 msb machine 进程残留（按 VM 名定向检查）
  # 宿主是 macOS（无 /proc）：用 ps -p 读命令行核验。
  # ps 读不到进程信息时不能判定通过 —— 视为残留，测试失败并保留现场排查。
  local pid ps_out found_pids=""
  for pid in $(pgrep -f "msb machine.*$vm_name" 2>/dev/null || true); do
    ps_out="$(ps -p "$pid" -o comm= -o args= 2>/dev/null || true)"
    if [[ -z "$ps_out" ]]; then
      echo "[-] 错误: PID $pid 匹配 $vm_name 但 ps 无法读取其进程信息，无法排除残留" >&2
      found_pids="$found_pids $pid(unknown)"
      continue
    fi
    # 命令名必须是 msb 且命令行包含该 VM 名才算本测试残留
    if [[ "$ps_out" == msb* && "$ps_out" == *"$vm_name"* ]]; then
      found_pids="$found_pids $pid"
    fi
  done
  if [[ -n "${found_pids// /}" ]]; then
    echo "[-] 错误: 测试 VM $vm_name 仍有残留 machine 进程:$found_pids (现场已保留，请手动排查)" >&2
    return 1
  fi

  echo "    - 进程检查: 已按 VM 名用 ps 核验，无 msb machine 残留"

  # 4. 验证宿主日常 VM `sb-default` 状态完全未受影响
  harness_find_msb
  echo "[+] 正在检查宿主默认环境状态 (只读确认 sb-default)..."
  local default_ls host_msb_home
  host_msb_home="${HOST_MSB_HOME:-$HOME/Data/sandboxes/msb}"
  default_ls="$(MSB_HOME="$host_msb_home" "$MSB_BIN" ls 2>&1 || true)"
  echo "$default_ls"

  if ! grep -q "sb-default" <<< "$default_ls"; then
    echo "[-] 错误: 宿主默认日常 VM sb-default 不见了!" >&2
    return 1
  fi

  echo "[+] 验证通过: 零残留且日常环境 sb-default 完好"
  return 0
}

# ------------------------------------------------------------------------------
# 完整自测流程 (单元 0 Acceptance 验收)
# ------------------------------------------------------------------------------
harness_self_test() {
  echo "========================================================================"
  echo "开始执行单元 0 端到端脚手架自测试 (Harness Self-Test)"
  echo "========================================================================"

  # 步骤 1: 建立独立临时 MSB_HOME 与配置
  harness_setup
  local vm_name="e2e-test-self-$$"
  E2E_VM_NAME="$vm_name"

  # 步骤 2: 准备假工作区 (包含两个相邻项目与假凭据)
  harness_setup_fake_workspace

  # 步骤 3: 在独立 MSB_HOME 中创建一次性 VM
  harness_create_vm "$vm_name"

  # 步骤 4: 在 VM 内执行命令并校验输出与退出码
  echo "[+] 测试 VM 内命令执行..."
  local exec_output
  exec_output="$(harness_exec "$vm_name" echo "E2E_HARNESS_OK")"
  if [[ "$exec_output" != *"E2E_HARNESS_OK"* ]]; then
    echo "[-] 错误: VM 命令输出不匹配: $exec_output" >&2
    return 1
  fi
  echo "[+] VM 命令执行成功，输出符合预期: $exec_output"

  # 步骤 5: 验证网络应用层断言原语
  echo "[+] 测试网络应用层断言原语..."
  if harness_assert_http "$vm_name" "http://1.1.1.1/" "301" 3 >/dev/null 2>&1; then
    echo "    - 公网 HTTP 断言测试通过 (可达目标返回 301)"
  else
    echo "    - [提示] 当前环境公网连接未放行或超时，跳过公网 HTTP 断言"
  fi
  harness_assert_http_blocked "$vm_name" "http://192.0.2.1:81/" 2
  echo "    - 拦截 HTTP 断言测试通过 (不可达目标未收到响应)"

  # 步骤 6: 验证 msb copy 坑点处理 (自动递归建父目录)
  echo "[+] 测试跨宿主安全文件复制 (带深层父目录)..."
  local test_copy_file="$E2E_WORKSPACE/fake-credentials/fake-token.json"
  harness_copy "$vm_name" "$test_copy_file" "/root/.config/nested/fake-token.json"
  local cat_output
  cat_output="$(harness_exec "$vm_name" cat "/root/.config/nested/fake-token.json")"
  if [[ "$cat_output" != *"dummy_mock_access_token"* ]]; then
    echo "[-] 错误: 复制文件内容验证失败: $cat_output" >&2
    return 1
  fi
  echo "[+] 文件复制及深层父目录自动创建成功"

  # 步骤 7: 显式触发清理
  local saved_vm_name="$vm_name"
  local saved_e2e_dir="$E2E_DIR"
  harness_cleanup

  # 步骤 8: 验收后清理验证
  E2E_DIR="$saved_e2e_dir"
  harness_verify_clean "$saved_vm_name"

  echo "========================================================================"
  echo "单元 0 自测试全部通过 (Exit Code 0)"
  echo "========================================================================"
  return 0
}

# ------------------------------------------------------------------------------
# 主入口处理 (支持作为脚本执行或被 source)
# ------------------------------------------------------------------------------
harness_main() {
  local cmd="${1:-self-test}"
  case "$cmd" in
    self-test)
      harness_self_test
      ;;
    setup)
      harness_setup "${2:-}"
      harness_setup_fake_workspace
      echo "E2E_DIR=$E2E_DIR"
      echo "E2E_MSB_HOME=$E2E_MSB_HOME"
      echo "E2E_MSB_CONFIG=$E2E_MSB_CONFIG"
      echo "E2E_WORKSPACE=$E2E_WORKSPACE"
      ;;
    cleanup)
      if [[ $# -lt 2 ]]; then
        echo "用法: $0 cleanup <E2E_DIR>" >&2
        exit 1
      fi
      E2E_DIR="$2"
      E2E_MSB_HOME="$E2E_DIR/msb-home"
      E2E_MSB_CONFIG="$E2E_DIR/microsandbox-config.json"
      harness_cleanup
      ;;
    -h|--help|help)
      cat <<EOF
用法: $0 [命令]

可用命令:
  self-test   执行完整的端到端脚手架空跑与自测 (默认)
  setup       仅建立独立环境并输出环境变量路径
  cleanup DIR 清理指定的测试根目录
EOF
      ;;
    *)
      echo "[-] 未知命令: $cmd (可使用 -h 查看帮助)" >&2
      exit 1
      ;;
  esac
}

# 判断是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  harness_main "$@"
fi
