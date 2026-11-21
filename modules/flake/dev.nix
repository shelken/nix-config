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
          feature-domains = {
            enable = true;
            name = "feature-domains";
            description = "modules/features 的一级目录只能是 ADR 0012 列出的领域";
            language = "fail";
            files = "^modules/features/(?!(nix|system|shell|cli|dev|editor|terminal|virt|desktop|input|network|secrets|backup|homelab|media|browser|social|write|ai)/)";
            entry = "一级目录不是领域（ADR 0012）；放进所属领域，或先改 ADR 与本钩子的领域清单";
          };
          feature-platform-split = {
            enable = true;
            name = "feature-platform-split";
            description = "功能不按平台拆成 darwin.nix/home.nix/nixos.nix";
            language = "fail";
            files = "^modules/features/.*/(darwin|home|nixos)\\.nix$";
            entry = "三端写在同一个文件（ADR 0012）；繁杂时拆出 _ 开头的私有片段";
          };
          feature-layout = {
            enable = true;
            name = "feature-layout";
            description = "功能的文件形式与模块名（ADR 0012）";
            files = "^(modules/features/|modules/profiles/|lint/feature-layout\\.py$)";
            pass_filenames = false;
            entry = "env AST_GREP=${pkgs.ast-grep}/bin/ast-grep ${pkgs.python3}/bin/python3 lint/feature-layout.py";
          };
          no-comments = {
            enable = true;
            name = "no-comments";
            description = "禁止新增代码注释，存量按棘轮基线自动收紧";
            files = "^(lint/no-comments\\.py|lint/no-comments-baseline\\.json|.*\\.(nix|py|sh|ts|lua))$";
            pass_filenames = false;
            entry = "env AST_GREP=${pkgs.ast-grep}/bin/ast-grep ${pkgs.python3}/bin/python3 lint/no-comments.py --tighten";
          };
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
          pi-compaction = {
            enable = true;
            name = "pi-compaction";
            description = "pi settings.json 的 enabledModels 变更时自动回填 reserveTokens";
            files = "^modules/features/ai/pi/settings\\.json$";
            pass_filenames = false;
            entry = "${pkgs.python3}/bin/python3 utils/script/just/sync_pi_compaction.py --pre-commit";
          };
        };
      };

      devShells.default = pkgs.mkShellNoCC {
        name = "dots";
        packages = with pkgs; [
          ast-grep
          bashInteractive
          deploy-rs
          nixfmt
          deadnix
          statix
          typos
          prettier
          nixos-anywhere
          actionlint
        ];
        shellHook = config.checks.pre-commit-check.shellHook;
      };

      formatter = pkgs.nixfmt-tree;
    };
}
