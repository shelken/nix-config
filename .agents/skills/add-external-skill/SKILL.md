---
name: add-external-skill
description: 获取外部skill
---

## when to use

- 需要引入外部skill

## 流程

1. 用户提供关于skill的链接，通常情况下是个github repo
2. 阅读相关代码 `nvfetcher.toml` `home/base/gui/dev/ai/skill.nix`
3. 在 nvfetcher.toml 添加 skill（按字母顺序），更新
   `nvfetcher -c nvfetcher.toml -f '^{the_skill_you_add}$'`
4. 在 skill.nix 添加引用，按字母顺序
5. `just hm` 更新并应用 home-manager
6. 一切没有问题就提交

## note

- 第三步nvfetcher更新时默认应该限定skill，因为 节省时间 且 限定范围不影响其他repo
