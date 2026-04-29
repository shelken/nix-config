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

## 补充 cli

当 skill 中涉及到cli的安装的时候，且当前 `home/base/gui/dev/ai/cli.nix`
中没有定义相关的`cli`，那么应该引入

1. 先检查nixpkgs是否已经有提到的cli工具，`nix-search-tv print | grep {cmd-cli-name}`，如果有**优先**使用nix来源，在
   `home.packages` 直接使用
2. 如果没有，则根据skill文档中的安装方式，如果是 bun/npm/uv 等方式，应该用npx/bunx/uvx直接封装，参考`cli.nix`当前已经写的例子，且要确保名字和skill中定义的一致，即skill写了怎么使用，那么到时候在shell中就应该怎么使用，例如包原名叫`bilibili-cli`，skill中的示例都是`bili`，那么最后在shell中的名字也就是
   `bili`

## note

- 第三步nvfetcher更新时默认应该限定skill，因为 节省时间 且 限定范围不影响其他repo
- cli 中的优先使用nix来源的前提是:
  nix可以直接使用已经编译好的二进制产物，因此应该检查是否不需要自己编译即可下载
- 当skill指明的要安装的依赖太大时，例如（libreoffice）时，应该向用户说明，并建议要用的时候才安装
