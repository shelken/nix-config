{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.mcp = {
      enable = true;
      servers = {
        context7 = {
          command = "npx";
          args = [
            "-y"
            "@upstash/context7-mcp"
          ];
          env.CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
          type = "stdio";
        };
        github = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-github"
          ];
          env.GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
          type = "stdio";
        };
      };
    };
  };
}
