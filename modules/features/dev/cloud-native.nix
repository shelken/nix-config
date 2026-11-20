{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.cloud-native ];

  flake.modules.homeManager.cloud-native =
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

        show_usage() {
          echo "Usage: skopeo-image-size <image-url> [os] [arch]"
          echo "Example: skopeo-image-size docker://docker.io/busybox:latest"
          echo "Example: skopeo-image-size docker://docker.io/busybox:latest linux arm64"
          echo ""
          echo "Calculate the total size of a container image in MB"
          echo "If os and arch are not provided, defaults to linux and current architecture"
        }

        if [ $# -eq 1 ]; then
          OS="linux"
          ARCH=$(uname -m)
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

        if [[ -z "$OS" || -z "$ARCH" || -z "$IMAGE_URL" ]]; then
          echo "Error: All arguments must be non-empty"
          show_usage
          exit 1
        fi

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

        if ! result=$(skopeo inspect --override-os="$OS" --override-arch="$ARCH" "$IMAGE_URL" 2>&1); then
          echo "Error: Failed to inspect image"
          echo "$result"
          exit 1
        fi

        if ! size_mb=$(echo "$result" | jq -r '
          .LayersData | map(.Size) | add / 1024 / 1024
        '); then
          echo "Error: Failed to parse image metadata"
          exit 1
        fi

        if [[ "$size_mb" == "null" || -z "$size_mb" ]]; then
          echo "Error: Could not determine image size"
          exit 1
        fi

        formatted_size=$(printf "%.2f" "$size_mb")

        echo "Total image size: $formatted_size MB"
      '';
    in
    {
      home.packages =
        (with pkgs; [
          dive
          lazydocker
          skopeo
        ])
        ++ [
          skopeo-image-size
        ];

      programs.k9s = {
        enable = true;

        plugins = {
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

      programs.kubecolor = {
        enable = true;
        enableAlias = true;
      };
    };
}
