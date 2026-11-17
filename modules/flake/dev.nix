{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = ../..;
        hooks = {
          nixfmt = {
            enable = true;
            settings.width = 100;
          };
          typos = {
            enable = true;
            settings = {
              write = true;
              configPath = "./.typos.toml";
            };
          };
          prettier = {
            enable = true;
            settings = {
              write = true;
              configPath = "./.prettierrc.yaml";
            };
          };
          # `/_` 是功能私有片段（ADR 0004）。别的功能要用它，说明接线放错了地方：
          # 该把它做成登记表条目或本功能的公开选项，而不是跨目录 import
          feature-private-imports = {
            enable = true;
            name = "feature-private-imports";
            description = "功能之间不 import 对方的私有文件";
            files = "^modules/features/.*\\.nix$";
            entry = "${pkgs.writeShellScript "check-feature-private-imports" ''
              if ${pkgs.gnugrep}/bin/grep -nE '\.\./[^"; ]*/_[^/"; ]+' "$@"; then
                echo '以上引用了其他功能的私有文件（路径含 /_），见 docs/adr/0004-dendritic-feature-modules.md' >&2
                exit 1
              fi
            ''}";
          };
          # 被平台属性禁用的 mod（如 macOS 上的 linux 模块）不会被 just 解析，错误要到另一个平台才暴露，
          # 所以对每个模块文件单独解析。模块引用根变量也会在这里报错
          just-modules = {
            enable = true;
            name = "just-modules";
            description = "justfile 与 just/*.just 逐个解析";
            files = "^(justfile|just/.*\\.just)$";
            pass_filenames = false;
            entry = "${pkgs.writeShellScript "check-just-modules" ''
              set -eu
              for f in justfile just/*.just; do
                ${pkgs.just}/bin/just --justfile "$f" --summary > /dev/null
              done
            ''}";
          };
        };
      };

      devShells.default = pkgs.mkShellNoCC {
        name = "dots";
        packages = with pkgs; [
          # mkShellNoCC 里没有交互式 bash，非交互 shell 会报错
          bashInteractive
          deploy-rs
          nixfmt
          deadnix
          statix
          typos
          prettier
          nixos-anywhere
          actionlint
          # 不要引入 nh：它会把 nix 一起带进来
        ];
        shellHook = config.checks.pre-commit-check.shellHook;
      };

      formatter = pkgs.nixfmt-tree;
    };
}
