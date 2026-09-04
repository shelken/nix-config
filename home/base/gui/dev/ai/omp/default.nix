{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;

  ompDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/omp";
in
{
  config = mkIf cfg.enable {
    # 别名：支持与 pi 并存，使用 sec-run omp
    home.shellAliases = {
      omp = "sec-run omp";
    };

    # 将 omp 的全局配置文件软链到本仓库的 config.yml（可直接编辑并由 git 管理）
    home.file.".omp/agent/config.yml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${ompDir}/config.yml";
      force = true;
    };

    # 将快捷键配置软链到本仓库的 keybindings.yml
    home.file.".omp/agent/keybindings.yml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${ompDir}/keybindings.yml";
      force = true;
    };

    # 将全局权限防护规则软链到本仓库的 permissions.yaml（可直接编辑并由 git 管理）
    home.file.".omp/agent/permissions.yaml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${ompDir}/permissions.yaml";
      force = true;
    };

    # 将 omp 插件清单软链到本仓库的 plugins/package.json（可直接编辑并由 git 管理）
    home.file.".omp/plugins/package.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${ompDir}/plugins/package.json";
      force = true;
    };

    # 自动化依赖安装：配置切换时静默确保 node_modules 就绪，无需手动敲命令
    home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f "$HOME/.omp/plugins/package.json" ]; then
        BUN="${pkgs.bun}/bin/bun"
        if command -v bun >/dev/null 2>&1; then
          BUN="$(command -v bun)"
        fi
        (cd "$HOME/.omp/plugins" && "$BUN" install --silent)
      fi
    '';

    # 引入 copy-cut 扩展（Shift+Alt+X 剪切输入框全文到剪贴板）
    home.file.".omp/agent/extensions/copy-cut.ts" = {
      source = ./extensions/copy-cut.ts;
      force = true;
    };

    # 引入 omp-guard 扩展（硬拦截高危命令与敏感机密路径）
    home.file.".omp/agent/extensions/guard.ts" = {
      source = ./extensions/guard.ts;
      force = true;
    };
    # 备份 omp 数据目录
    shelken.backup.app.omp = [
      "${config.home.homeDirectory}/.omp"
    ];
  };
}
