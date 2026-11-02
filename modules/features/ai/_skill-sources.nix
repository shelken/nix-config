# 外部 skill 来源声明（纯数据）。单一事实来源：
#   - modules/features/ai/skill.nix 用它装配 Home 链接
#   - 同一个文件里的 flake.skillSourceDirs 用它算出「input → 启用的 skill 目录」，
#     Renovate PR 的文件展示 workflow 读后者决定内联哪些目录的改动
# input 名即 flake input 名（也是 Renovate 的 depName）；文件的 rev 由 flake.nix 锁定。
# 每个分组：
#   input        提供文件的 flake input 名
#   base         分组内容在仓库内的路径前缀（"." 表示仓库根）
#   skills       显式声明的 skill：名字 → base 内的相对路径
#   discover     true 时改为在 base 下递归扫描含 SKILL.md 的目录（eval 期扫上游源码）
#   exclude      从该分组里去掉的 skill 名
#   derived      该分组的部署内容来自 build 期改写后的派生树，值是该树对应的仓库内前缀
#   frontmatter  对指定 skill 覆盖 frontmatter 字段
{
  anti-slop = {
    input = "anti-slop";
    base = ".";
    skills.install-anti-slop = "skills/install-anti-slop";
    frontmatter.install-anti-slop.disable-model-invocation = true;
  };

  # pstack 把 CLI/TUI 验收委托给这个 skill；只取 control-cli，
  # control-ui 由本机 agent-browser 承担，见 skills/pstack-harness。
  cursor-team-kit = {
    input = "cursor-plugins";
    base = "cursor-team-kit/skills";
    skills.control-cli = "control-cli";
  };

  diagram-design = {
    input = "diagram-design";
    base = ".";
    skills.diagram-design = "skills/diagram-design";
  };

  humanlayer-skills = {
    input = "humanlayer-skills";
    base = ".";
    skills = {
      design-control-loop = "plugins/design-control-loop/skills/design-control-loop";
      show-me = "plugins/show-me/skills/show-me";
    };
    frontmatter.show-me.disable-model-invocation = false;
    # skills.visual-pr = "plugins/visual-pr/skills/visual-pr";
  };

  llamaparse-agent-skills = {
    input = "llamaparse-agent-skills";
    base = "skills";
    skills.liteparse = "liteparse";
  };

  mattpocock-skills = {
    input = "mattpocock-skills";
    base = ".";
    skills = {
      improve-codebase-architecture = "skills/engineering/improve-codebase-architecture";
      codebase-design = "skills/engineering/codebase-design";
      diagnosing-bugs = "skills/engineering/diagnosing-bugs";
      grill-me = "skills/productivity/grill-me";
      grill-with-docs = "skills/engineering/grill-with-docs";
      grilling = "skills/productivity/grilling";
      handoff = "skills/productivity/handoff";
      prototype = "skills/engineering/prototype";
      tdd = "skills/engineering/tdd";
      to-tickets = "skills/engineering/to-tickets";
      to-spec = "skills/engineering/to-spec";
      writing-for-agents = "skills/productivity/writing-for-agents";
      loop-me = "skills/in-progress/loop-me";
      code-review = "skills/engineering/code-review";
      implement = "skills/engineering/implement";
      implement-spec = "skills/engineering/implement-spec";
      setup-matt-pocock-skills = "skills/engineering/setup-matt-pocock-skills";
      wayfinder = "skills/engineering/wayfinder";
      research = "skills/engineering/research";
      domain-modeling = "skills/engineering/domain-modeling";
      ask-matt = "skills/engineering/ask-matt";
      triage = "skills/engineering/triage";
      retro = "skills/engineering/retro";
      pr = "skills/engineering/pr";
    };
  };

  pstack = {
    # 上游是 Cursor 方言：正文引用 Task/AskQuestion/~/.cursor/rules 等本机不存在的东西。
    # build 期插入指针并改写死链，派生树对应仓库里的 pstack/。
    input = "cursor-plugins";
    base = "pstack/skills";
    derived = "pstack";
    discover = true;
    exclude = [
      "tdd"
    ];
    frontmatter.poteto-mode.name = "poteto-mode";
    frontmatter.make-bot-ui.name = "make-bot-ui";
    frontmatter.setup-pstack.disable-model-invocation = true;
  };

  security-audit-skill = {
    input = "security-audit-skill";
    base = ".";
    skills.security-audit = "skills/security-audit";
    frontmatter.security-audit.disable-model-invocation = true;
  };
}
