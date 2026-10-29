# skills

本仓库自管的 agent 技能源目录，由 `../skill.nix` 部署到各 agent

## 目录结构

- `<name>/SKILL.md`：单个技能正文，目录名与 frontmatter 的 `name` 严格一致
- `<name>/README.md`：可选文件；自研技能记录设计决策，外部拷贝并调整过的技能记录上游来源与差异清单
- `../skill.nix`：声明外部技能来源与部署目标，外部版本由仓库根目录的 `nvfetcher.toml` 锁定

## 外部拷贝技能的来源记录

外部拷贝并改过的技能，在 `SKILL.md` 同目录放 `README.md`
- 首段注明上游仓库、路径及导入时的 commit
- 随后以「与上游的差异」逐项列出改动，未变动文件一并说明
- 修改此类技能时，同步更新差异清单

与上游完全一致的技能不放在本目录，在 `nvfetcher.toml` 和 `../skill.nix` 中引入，流程见 `add-external-skill`

列出现有的外部拷贝技能

```bash
grep -l '与上游的差异' */README.md
```

### 确定导入 commit

执行 `git clone --filter=blob:none --no-checkout <上游>` 后，通过 `git ls-tree -r <commit> -- <路径>` 计算 blob 哈希，与本地导入提交中对应文件的哈希比对，一致的提交即为导入时的上游状态

`SKILL.md` 已改写无法直接比对时，使用未改动文件的哈希和导入日期推定，并在 README 中注明「推定」
