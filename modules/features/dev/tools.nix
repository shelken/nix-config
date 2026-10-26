# 共享工具登记表：接口声明与宿主生成器（ADR 0003）
# 接口会被 ai（omp/pi/codex 等）等多个功能写入，按「接口放 core」（ADR 0004）
# 挂到 darwin/nixos 的 core；第一批 Nix 条目在 tools-base.nix。
{
  config,
  ...
}:

{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tools ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.tools ];

  flake.modules.homeManager.tools =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.shelken.dev.tools;
    in
    {
      options.shelken.dev.tools = lib.mkOption {
        description = "共享工具登记表：宿主与 Agent 沙箱共享的工具清单";
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options = {
                package = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = if config.mise != null then null else name;
                  description = "nixpkgs 属性名，默认取登记名；与 mise 互斥";
                };

                mise = lib.mkOption {
                  type = lib.types.nullOr lib.types.anything;
                  default = null;
                  description = "mise 工具规格（版本字符串或规格属性集），与 package 互斥";
                };

                files = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                  description = "随工具进入沙箱的配置文件，宿主侧照常作为 home.file";
                };

                postInstall = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  description = "安装后脚本，宿主在激活时运行，沙箱在 sb sync 时运行";
                };
              };
            }
          )
        );
      };

      options.shelken.dev.sandbox.hostCommands = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "宿主控制命令表（命令名 -> 沙箱内执行时的报错原因说明）";
      };

      options.shelken.dev.sandbox.writableRoots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          沙箱里整体可写的配置根（相对 $HOME，如 ".omp/agent"）。
          落在数据盘上、所有上下文共用；其中登记表 files 声明的路径逐项只读挂载在根上。
          launcher 只执行发布出去的这份清单，根的增删只改 Nix。
        '';
      };

      config = lib.mkMerge [
        {
          # 校验：缺失字段与互斥字段断言
          assertions = lib.concatLists (
            lib.mapAttrsToList (name: tool: [
              {
                assertion = !(tool.package != null && tool.mise != null);
                message = "shelken.dev.tools.${name}: 不能同时指定 package 与 mise（字段互斥）";
              }
              {
                assertion = (tool.package != null || tool.mise != null) || (tool.files != { });
                message = "shelken.dev.tools.${name}: 必须指定 package 或 mise 之一，或声明 files（纯配置条目）";
              }
            ]) cfg
          );

          # 宿主生成器：Nix 条目进 home.packages
          home.packages = lib.concatMap (tool: lib.optional (tool.package != null) pkgs.${tool.package}) (
            builtins.attrValues cfg
          );

          # 宿主生成器：mise 条目进 programs.mise.globalConfig.tools
          programs.mise.globalConfig.tools = lib.listToAttrs (
            lib.concatMap (
              name:
              let
                tool = cfg.${name};
              in
              lib.optional (tool.mise != null) (
                if builtins.isAttrs tool.mise then
                  if tool.mise ? name then
                    {
                      name = tool.mise.name;
                      value = builtins.removeAttrs tool.mise [ "name" ];
                    }
                  else
                    {
                      inherit name;
                      value = tool.mise;
                    }
                else
                  {
                    inherit name;
                    value = tool.mise;
                  }
              )
            ) (builtins.attrNames cfg)
          );

          # 宿主生成器：postInstall 进 home.activation
          home.activation = lib.listToAttrs (
            lib.concatMap (
              name:
              let
                tool = cfg.${name};
              in
              lib.optional (tool.postInstall != null && tool.postInstall != "") {
                name = "tool-postInstall-${name}";
                value = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
                  # HM 的 activate 把 PATH 重置成自己的工具链，不继承用户 shell；mise 的 PATH hook 随之丢失。
                  # gh/git 由 Nix 注入；bun 等 mise 工具（ADR 0003 单一来源，不把 Nix Bun 带进闭包）经 shims 目录解析
                  export PATH="${
                    lib.makeBinPath (
                      with pkgs;
                      [
                        gh
                        git
                      ]
                    )
                  }:$HOME/.local/share/mise/shims:$PATH"
                  ${tool.postInstall}
                '';
              }
            ) (builtins.attrNames cfg)
          );

          # 宿主生成器：files 随工具照常作为 home.file
          home.file = lib.mkMerge (lib.mapAttrsToList (_: tool: lib.mkIf (tool.files != { }) tool.files) cfg);
        }
      ];
    };
}
