{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
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

            如果仅用标题行就能准确表达变更内容，则不要在信息正文中包含任何内容。只有当正文提供*有用*信息时才使用它。

            如果你不知道哪个diff命令，你可以参考：`git -P diff --cached`

            不要在正文中重复标题行的信息。

            在回复中只返回提交信息。不要包含任何关于此任务的额外元评论。不要在提交信息中包含原始差异输出。

            遵循良好的 Git 风格：

            - 用空行分隔标题和正文
            - 尽量将标题行限制在 50 个字符以内
            - 不要在标题行末尾添加任何标点符号
            - 正文每行限制在 72 个字符内
            - 保持正文简短扼要（如果无用则完全省略）
            - 标题和正文使用中文
            - 使用`conventional commits`的格式提交
            - 标题开头加上合适的 Emoji
          '';
        };
      };
    };

    # home.sessionVariables = {
    # };
  };
}
