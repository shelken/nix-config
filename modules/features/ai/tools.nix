# 共享工具登记表：ai 侧条目（omp/pi/codex/claude-code/bun，ADR 0003）
# omp postInstall 承接原 home.activation.installOmpPlugins 的插件补齐逻辑。
{
  config,
  lib,
  ...
}:
{
  flake.modules.homeManager.ai.shelken.dev.tools = {
    # mise 共享工具
    # 1.3.13 无 BUN_CONFIG_HTTP_IDLE_TIMEOUT，安装会在半开连接上永久挂起
    bun.mise = "1.4.2";
    codex.mise = "0.160.1";
    claude-code.mise = "2.1.304";
    omp = {
      mise = {
        name = "oh-my-pi";
        version = "latest";
        minimum_release_age = "0h";
      };
      # 插件按仓库清单 bun install 补齐（只补缺，不删除现有依赖）：
      # 沙箱内手装的插件与已从清单删除的插件不被清理。
      # 清单用普通副本而非软链，否则 bun install 会写穿到仓库文件；
      # 但 store 里的源文件是只读的，cp 在目标不存在时会连权限一起继承（444），
      # 导致 bun install 报 EACCES，故复制后必须显式补可写位。
      postInstall = ''
        # 与 OMP 的解析一致：$XDG_DATA_HOME/omp 存在时插件在其下（沙箱），否则在 ~/.omp/plugins（宿主）
        # 判据来源：@oh-my-pi/pi-utils 的 getPluginsDir() → DirResolver；OMP 改判据时这里要跟着改
        if [[ -n "''${XDG_DATA_HOME:-}" && -d "$XDG_DATA_HOME/omp" ]]; then
          plugins="$XDG_DATA_HOME/omp/plugins"
        else
          plugins="$HOME/.omp/plugins"
        fi
        mkdir -p "$plugins/node_modules"
        if [[ ! -f "$plugins/package.json" ]] || ! cmp -s ${./omp/plugins/package.json} "$plugins/package.json"; then
          cp -f ${./omp/plugins/package.json} "$plugins/package.json"
          chmod u+w "$plugins/package.json"
        fi
        # Bun 对缓存里已有的 git 裸仓库只 fetch 到 FETCH_HEAD，不更新 refs/heads/main，#main 永远解析成首次克隆的提交
        # （上游缺陷 #11548）。只删 git 条目（*.git 裸仓库、@G@<sha> 提取目录）强制重新克隆；
        # npm 包条目跨激活保留，否则每次激活要重下全部 npm 包（实测约 35s → 5s）。
        # 上游修复 oven-sh/bun#44968 于 2026-10-14 合并，未进 1.4.3；bun ≥ 1.4.4 后实测
        # 不删 git 条目也能跟上 main（修复面向 bun update，可能需改用它），即可删掉下面这行
        rm -rf "$plugins/.bun-cache"/*.git "$plugins/.bun-cache"/@G@*
        # Bun 下载缓存共用：沙箱侧落到共用 mise 层；宿主激活走默认 HOME 缓存
        bunCache="''${SB_BUN_CACHE_DIR:-$HOME/.omp/.bun-cache}"
        mkdir -p "$bunCache"

        # 依赖安装脚本一律不执行：node-pty 在 Linux 无预编译产物，
        # 装它要回落 node-gyp 编译；guest 补 C 工具链的闭包增量实测 1.3 GiB
        # （gcc-wrapper 370 MiB + binutils 121 MiB + isl/mpfr/mpc/gcc), 超出 200 MiB 预算。
        # 跳过脚本不影响其余纯 JS 插件的加载；node-pty 仅供终端桥接，非插件加载必需。

        # git 源依赖：bun 对 GitHub 依赖优先走 tarball API，该请求不带 git 凭据，
        # 私有仓库必然 404（上游缺陷 oven-sh/bun#19618）。这里改为 git clone（凭据由
        # GIT_CONFIG_GLOBAL 的 insteadOf 注入）后以 file: 依赖安装，绕开该路径。
        # .git-vendor 复用：本地已 clone 且 ref 一致就跳过 clone —— 补装缺失插件时
        # 不必重新拉取其余依赖。
        # clone 失败（无有效凭据、仓库不可达等）只警告并继续，不区分原因、不影响退出码。
        # 注意 guest 内 GITHUB_TOKEN 的值是字面占位符 $MSB_GITHUB_TOKEN，不能靠变量非空判断。
        git_vendor="$plugins/.git-vendor"
        mkdir -p "$git_vendor"
        git_deps_json="[]"
        while IFS= read -r entry; do
          dep_name="$(jq -r '.[0]' <<< "$entry")"
          dep_spec="$(jq -r '.[1]' <<< "$entry")"
          # 去掉 ref fragment（#main）后再拼 clone 地址
          repo_path="$(printf '%s' "$dep_spec" | sed -E 's/#.*$//' \
            | sed -E 's#^git\+ssh://git@github\.com/##; s#^git@github\.com:##; s#^ssh://git@github\.com/##; s#^git\+https://github\.com/##; s#^https://github\.com/##')"
          repo_ref="$(printf '%s' "$dep_spec" | sed -nE 's/.*#(.+)$/\1/p')"
          https_url="https://github.com/$repo_path"
          dest="$git_vendor/$dep_name"
          mkdir -p "$(dirname "$dest")"
          if [[ -d "$dest" && -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$repo_ref" ]]; then
            # 本地已有同 ref 副本：直接复用，不发起网络请求
            git_deps_json="$(jq -c --arg n "$dep_name" --arg v "file:$dest" '. + [[$n, $v]]' <<< "$git_deps_json")"
            continue
          fi
          rm -rf "$dest"
          clone_args=(--depth 1)
          [[ -n "$repo_ref" ]] && clone_args+=(--branch "$repo_ref")
          if clone_out="$(GIT_TERMINAL_PROMPT=0 git clone "''${clone_args[@]}" "$https_url" "$dest" 2>&1)"; then
            rm -rf "$dest/.git"
            printf '%s\n' "$repo_ref" > "$dest/.ref"
            git_deps_json="$(jq -c --arg n "$dep_name" --arg v "file:$dest" '. + [[$n, $v]]' <<< "$git_deps_json")"
          else
            rm -rf "$dest"
            echo "[!] 警告: 私有插件 ''${dep_name} 未能拉取，跳过 (''${repo_path}): $clone_out"
          fi
        done < <(jq -c '.dependencies // {} | to_entries
              | map(select(.value | test("^(git\\+|git@|ssh://)")))
              | .[] | [.key, .value]' "$plugins/package.json")

        # 一次性安装：npm 源依赖 + clone 成功的 git 源依赖（clone 失败的不进依赖表）
        jq --argjson git "$git_deps_json" '
          (.dependencies // {}) |= with_entries(select(.value | test("^(git\\+|git@|ssh://)") | not))
          | reduce $git[] as $e (.; .dependencies[$e[0]] = $e[1])
        ' "$plugins/package.json" > "$plugins/package.json.install"
        mv "$plugins/package.json.install" "$plugins/package.json"

        # 沙箱 sync 之外（宿主激活）容忍整体失败，避免打断日常开关机；
        # 沙箱 sync 设置 SB_POSTINSTALL_STRICT=1，失败必须传给 sb sync
        if [ -n "''${SB_POSTINSTALL_STRICT:-}" ]; then
          BUN_INSTALL_CACHE_DIR="$bunCache" bun install --cwd "$plugins" --ignore-scripts --silent
        else
          BUN_INSTALL_CACHE_DIR="$bunCache" bun install --cwd "$plugins" --ignore-scripts --silent 2>/dev/null || true
        fi
      '';
    };
    pi = {
      mise = {
        name = "npm:@earendil-works/pi-coding-agent";
        version = "latest";
        minimum_release_age = "0h";
      };
    };
  };
}
