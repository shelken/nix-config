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
          # 仓库自定义规则按语法树匹配，规则与正反样例见 lint/README.md
          ast-grep = {
            enable = true;
            name = "ast-grep";
            description = "仓库自定义 lint 规则";
            files = "\\.nix$";
            entry = "${pkgs.ast-grep}/bin/ast-grep scan";
          };
          ast-grep-test = {
            enable = true;
            name = "ast-grep-test";
            description = "lint 规则的正反样例";
            files = "^(sgconfig\\.yml|lint/.*\\.yml)$";
            pass_filenames = false;
            entry = "${pkgs.ast-grep}/bin/ast-grep test --skip-snapshot-tests";
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
