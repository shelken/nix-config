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
          总结**暂存区**代码并且提交
          如果你不知道哪个diff命令，你可以参考：`git diff --staged`
          - **格式:** `<type>(<scope>): <subject>`
            - `<type>`: 提交类型 (如 `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`)。
            - `(<scope>)`: 可选的作用域，用于说明本次提交影响的范围 (如 `home`, `modules`, `agent`)。
            - `<subject>`: 简明扼要的英文标题。
          - **正文 (Body):**
            - 使用中文编写，简要描述变更的具体内容，挑重点描述
            - 与标题之间空一行。
        '';
      };
    };
  };

  # home.sessionVariables = {
  # };
}
