{
  ...
}:
let

in
{
  programs.gemini-cli = {
    enable = true;
    commands = {
      # "" = {
      #   description = "";
      #   prompt = ''

      #   '';
      # };
      "git/commit" = {
        description = "总结暂存区代码并且提交";
        prompt = ''
          总结暂存区代码并且提交
          为了保持提交历史的清晰和一致，请遵循 [Conventional Commits](https://www.conventionalcommits.org/)规范。
          - **格式:** `<type>(<scope>): <subject>`
            - `<type>`: 提交类型 (如 `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`)。
            - `(<scope>)`: 可选的作用域，用于说明本次提交影响的范围 (如 `home`, `modules`, `agent`)。
            - `<subject>`: 简明扼要的英文标题。
          - **正文 (Body):**
            - 使用中文编写，详细描述变更的原因、目的和具体内容。
            - 与标题之间空一行。
            - 以**无序列表**格式叙述
            - 简洁描述做了哪些事，但不要解释过多，也不要对一些极其简单、重复且不重要的代码提及
        '';
      };
    };
  };

  # home.sessionVariables = {
  # };
}
