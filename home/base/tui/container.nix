{
  pkgs,
  lib,
  config,
  ...
}:
let
  skopeo-image-size = pkgs.writeShellScriptBin "skopeo-image-size" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # 显示使用说明
    show_usage() {
      echo "Usage: skopeo-image-size <image-url> [os] [arch]"
      echo "Example: skopeo-image-size docker://docker.io/busybox:latest"
      echo "Example: skopeo-image-size docker://docker.io/busybox:latest linux arm64"
      echo ""
      echo "Calculate the total size of a container image in MB"
      echo "If os and arch are not provided, defaults to linux and current architecture"
    }

    # 设置默认值
    if [ $# -eq 1 ]; then
      OS="linux"
      # 获取当前系统架构
      ARCH=$(uname -m)
      # 标准化架构名称，无匹配时使用amd64
      case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        arm64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        armv6l) ARCH="arm" ;;
        *) ARCH="amd64" ;;
      esac
      IMAGE_URL="$1"
    elif [ $# -eq 3 ]; then
      IMAGE_URL="$1"
      OS="$2"
      ARCH="$3"
    else
      echo "Error: Invalid number of arguments"
      show_usage
      exit 1
    fi

    # 验证参数
    if [[ -z "$OS" || -z "$ARCH" || -z "$IMAGE_URL" ]]; then
      echo "Error: All arguments must be non-empty"
      show_usage
      exit 1
    fi

    # 检查必要的命令是否存在
    if ! command -v skopeo >/dev/null 2>&1; then
      echo "Error: skopeo is not installed or not in PATH"
      exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
      echo "Error: jq is not installed or not in PATH"
      exit 1
    fi

    echo "Inspecting image: $IMAGE_URL"
    echo "OS: $OS, Architecture: $ARCH"
    echo "Executing: skopeo inspect --override-os=\"$OS\" --override-arch=\"$ARCH\" \"$IMAGE_URL\""

    # 执行镜像检查并计算大小
    if ! result=$(skopeo inspect --override-os="$OS" --override-arch="$ARCH" "$IMAGE_URL" 2>&1); then
      echo "Error: Failed to inspect image"
      echo "$result"
      exit 1
    fi

    # 计算总大小（MB）
    if ! size_mb=$(echo "$result" | jq -r '
      .LayersData | map(.Size) | add / 1024 / 1024
    '); then
      echo "Error: Failed to parse image metadata"
      exit 1
    fi

    # 格式化输出
    if [[ "$size_mb" == "null" || -z "$size_mb" ]]; then
      echo "Error: Could not determine image size"
      exit 1
    fi

    # 四舍五入到两位小数
    formatted_size=$(printf "%.2f" "$size_mb")

    echo "Total image size: $formatted_size MB"
  '';
in
{
  config = lib.mkIf config.shelken.dev.cloud-native.enable {
    home.packages =
      (with pkgs; [
        dive # A tool for exploring each layer in a docker image
        lazydocker # docker管理
        skopeo
      ])
      ++ [
        skopeo-image-size
      ];

    programs.k9s = {
      enable = true;

      plugins = {
        # 为选中的pod在当前命名空间创建调试容器
        # 参见 https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#ephemeral-container
        debug = {
          shortCut = "Shift-D";
          description = "Add debug container";
          dangerous = true;
          scopes = [ "containers" ];
          command = "bash";
          background = false;
          confirm = true;
          args = [
            "-c"
            "kubectl debug -it --context $CONTEXT -n=$NAMESPACE $POD --target=$NAME --image=nicolaka/netshoot:v0.14 --profile=sysadmin --share-processes -- bash"
          ];
        };
      };
    };
    # catppuccin.k9s.transparent = true;

    programs.kubecolor = {
      enable = true;
      enableAlias = true;
    };
  };
}
