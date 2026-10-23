{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      mylib,
      ...
    }:
    let
      # 软链仓库内文件，仓库中直接编辑即生效
      linkOmp = rel: mylib.mkConfigFile config (./. + "/${rel}");

      # 扩展目录内除 *.test.ts 外的 .ts 逐个软链；目录内还含测试与 AGENTS.md，不能整目录软链
      extensionFiles = builtins.attrNames (
        lib.filterAttrs (
          name: type: type == "regular" && lib.hasSuffix ".ts" name && !lib.hasSuffix ".test.ts" name
        ) (builtins.readDir ./extensions)
      );
      extensionLinks = lib.listToAttrs (
        map (name: {
          name = ".omp/agent/extensions/${name}";
          value = linkOmp "extensions/${name}";
        }) extensionFiles
      );
    in
    {
      config = {
        programs.zsh.initContent = ''
          # for mnemopi gemini embedding
          export MNEMOPI_EMBEDDING_DIM=3072
        '';
        # 别名：支持与 pi 并存，使用 sec-run omp
        home.shellAliases = {
          omp = "sec-run omp";
        };

        programs.mise.globalConfig.tools.oh-my-pi = {
          version = "latest";
          minimum_release_age = "0h";
        };

        home.file = {
          # omp 全局配置 / 快捷键 / 权限防护规则
          # 插件清单不在此列：它必须是普通副本，软链会被 omp plugin install 写穿到仓库
          ".omp/agent/config.yml" = linkOmp "config.yml";
          ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
          ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
          # 模型配置: provider 清单 + 自定义模型 (apiKey 为环境变量名, OMP resolveConfigValue 先查 env 后降级字面量)
          ".omp/agent/models.yml" = linkOmp "models.yml";
          ".omp/agent/context-prune/settings.json" =
            mylib.mkConfigFile config ../pi/configs/context-prune.json;
          # ".omp/agent/mcp.json" = linkOmp "mcp.json";
        }
        // extensionLinks;

        # 插件目录以仓库清单为准：每次激活重放清单并重装，手装插件随之消失。
        # 清单用普通副本而非软链，否则 omp plugin install 会写穿到仓库文件；
        # 但 store 里的源文件是只读的，cp 在目标不存在时会连权限一起继承（444），
        # 导致 bun install 报 EACCES，故复制后必须显式补可写位。
        # bun install 不会移除多余包，所以 node_modules 直接删掉重建。
        home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
          githubToken="$(${pkgs.gh}/bin/gh auth token)"
          plugins="$HOME/.omp/plugins"
          mkdir -p "$plugins"
          rm -rf "$plugins/node_modules" "$plugins/bun.lock" "$plugins/omp-plugins.lock.json"
          cp -f ${./plugins/package.json} "$plugins/package.json"
          chmod u+w "$plugins/package.json"
          # Bun 对缓存里已有的 git 裸仓库只 fetch 到 FETCH_HEAD，不更新 refs/heads/main，#main 永远解析成首次克隆的提交
          # （上游缺陷 #11548）。只删 git 条目（*.git 裸仓库、@G@<sha> 提取目录）强制重新克隆；
          # npm 包条目跨激活保留，否则每次激活要重下全部 npm 包（实测约 35s → 5s）。
          # 上游修复 oven-sh/bun#44968 于 2026-10-14 合并，未进 1.4.3；bun ≥ 1.4.4 后实测
          # 不删 git 条目也能跟上 main（修复面向 bun update，可能需改用它），即可删掉下面这行
          rm -rf "$plugins/.bun-cache"/*.git "$plugins/.bun-cache"/@G@*
          PATH="${pkgs.git}/bin:$PATH" GITHUB_TOKEN="$githubToken" BUN_INSTALL_CACHE_DIR="$plugins/.bun-cache" \
            ${pkgs.bun}/bin/bun install --cwd "$plugins" --silent
          unset githubToken
        '';

        shelken.backup.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
      };
    };
}
