{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    sops.templates."mcp/mcp.json" = {
      content = builtins.toJSON {
        mcpServers = {
          context7 = {
            command = "npx";
            args = [
              "-y"
              "@upstash/context7-mcp"
            ];
            env = {
              CONTEXT7_API_KEY = config.sops.placeholder."context7/api-key";
            };
          };
          github = {
            command = "npx";
            args = [
              "-y"
              "@modelcontextprotocol/server-github"
            ];
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = config.sops.placeholder."github/cli-token";
            };
          };
        };
      };
      path = "${config.xdg.configHome}/mcp/mcp.json";
      mode = "0600";
    };
  };
}
