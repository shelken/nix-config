# Mise 版本管理器：跨平台 CLI
{ config, ... }:
{
  # 原属 gui 全覆盖，跨平台无 darwin 专属
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.mise ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.mise ];

  flake.modules.homeManager.mise = {
    programs.mise = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;

      globalConfig = {
        # 让 mise 的工具路径始终排在前,避免 brew/其他 PATH 修改盖过 mise 声明的版本。
        # 解决场景:某工具同时在 brew 和 mise 声明时,brew 路径抢先导致 mise 版本锁定失效。
        settings.activate_aggressive = true;
        # 不把全局 shims 目录放进 PATH。shim 全局共用一份，版本声明却是项目级的，
        # 项目外的调用会命中孤儿 shim 报 "No version is set for shim"。
        # zsh 首次初始化时另有 path 过滤（modules/features/shell/zsh/default.nix）
        # 处理 omz 插件加载瞬间；这里防止之后 mise activate 再把 shims 加回 PATH，
        # 否则用户随便跑个命令触发 rehash 就会重新暴露孤儿 shim。
        settings.activate_shims = false;
        # bun 由共享工具登记表提供（shelken.dev.tools，ADR 0003），此处不再声明
        tools = {
          yt-dlp = "2026.08";
          "github:shelken/proxy" = {
            version = "latest";
            matching = "sbtools";
            minimum_release_age = "0h";
          };
          "cargo:mbx" = "1.18"; # for cargo build, save storage
        };
      };
    };
    home.shellAliases = {
      cargo = "mbx";
    };
  };
}
