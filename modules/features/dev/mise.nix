{ config, ... }:
let
  # renovate: datasource=github-releases depName=rust-lang/rust
  rustVersion = "1.100";
in
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.mise ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.mise ];

  flake.modules.homeManager.mise = {
    programs.mise = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;

      globalConfig = {
        settings.activate_aggressive = true;
        # 不把全局 shims 目录放进 PATH。shim 全局共用一份，版本声明却是项目级的，
        # 项目外的调用会命中孤儿 shim 报 "No version is set for shim"。
        settings.activate_shims = false;
        tools = {
          # renovate: datasource=github-releases depName=yt-dlp/yt-dlp
          yt-dlp = "2026.08";
          rust = {
            version = rustVersion;
            mr_boxington = true;
            components = "rust-analyzer";
          };
          # renovate: datasource=github-releases depName=jdx/mr-boxington
          mr-boxington = "1.30";
        };
      };
    };
  };
}
