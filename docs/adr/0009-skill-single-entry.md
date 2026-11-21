# skill 只有一个入口：shelken.dev.ai.skills

日期: 2026-11-15

skill 原有三个入口：`ai/skills/` 目录自动扫描、`_skill-sources.nix` 外部 skill 中心清单、`shelken.dev.ai.skills` 功能登记。前两者装到所有导入 `ai` 的机器，外部 skill 无法随功能部署。现在 `shelken.dev.ai.skills` 是唯一入口：一个 skill 列表，谁需要某个 skill 就由谁声明，`ai` 的通用 skill 在 `skill.nix` 声明

## 规则

- 声明 MUST 写在 Home Manager 模块里：`shelken.dev.ai.skills = [ <来源> … ]`，来源是路径字面量、input 里的目录字符串或派生
- skill 名 MUST 默认取来源的目录名；要改 frontmatter 或名字时写 `{ source; name; frontmatter; }`，派生来源 MUST 写 `name`
- 路径字面量指本仓库内的本地 skill，部署 MUST 走 `mylib.mkConfigLink`（liveEdit 时软链回工作树）；字符串与派生原样部署
- 批量登记用 `mylib.discoverSkills <目录> { exclude; frontmatter; }`：递归查找含 `SKILL.md` 的目录，嵌套目录名的 `/` 换成 `--`；`exclude` 与 `frontmatter` 写不存在的名字时求值失败
- 重名时求值失败（部署前断言）
- 派生来源 MUST 手写 `upstream`（上游目录），CI 据此展示上游改动；字符串来源自动取 `source`
- 部署 MUST 平铺，`skillTargets` 只列目标目录，MUST NOT 分组

## CI

Renovate PR 的 diff 过滤不读中心清单：`utils/script/skill_source_dirs.py` 逐台主机求值 `flake.skillUpstreams.<host>`（禁用 IFD，不构建），用 `flake.lock` 的 narHash 算出各 input 的 store 路径来归属上游目录。求值失败的主机 MAY 跳过，MUST 给出 warning

## 考虑过的替代方案

- 声明移到 flake-parts 层：CI 不必求值主机，但为 CI 改变调用方写法
- 不经主机合并求值全部 HM 模块：功能脱离真实主机求值失败
- 保留 `flatten = false` 分组形态：没有目标在用，分组名来自已删除的中心清单

## 后果

- 外部 skill 能随功能部署
- 取代 ADR 0006 中「skill 用哪个 input 声明在 `_skill-sources.nix`」与「workflow 按 `flake.skillSourceDirs`」两处说法
- 被跳过主机上独有的外部 skill，上游改动不会出现在 Renovate PR 评论里
