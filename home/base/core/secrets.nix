{
  mylib,
  config,
  lib,
  sops-nix,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;

  enabledSecrets = [
    "github/cli-token"
    # "chat-api/api-key"
    "context7/api-key"
    "deepseek/api-key"
    "dashscope/api-key"
    # "gemini/api-key"
    "groq/api-key"
    "modelscope/api-key"
    # "moonshot/api-key"
    # "openrouter/api-key"
    # "zhipu/api-key"
    # "tavily/api-key"
  ];

in
{
  imports = [
    # agenix.darwinModules.default
    # agenix.homeManagerModules.default
    # sops-nix
    sops-nix.homeManagerModules.sops
  ];
  options.shelken.secrets = {
    enable = mkBoolOpt false "Whether or not use secrets";
  };
  config = mkIf cfg.enable (
    let
      shellInit = ''
        export GH_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
        export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
        export HOMEBREW_GITHUB_API_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
        # ai api key
        export CONTEXT7_API_KEY="$(cat ${config.sops.secrets."context7/api-key".path})"
        export DEEPSEEK_API_KEY="$(cat ${config.sops.secrets."deepseek/api-key".path})"
        export DASHSCOPE_API_KEY="$(cat ${config.sops.secrets."dashscope/api-key".path})"
        export GROQ_API_KEY="$(cat ${config.sops.secrets."groq/api-key".path})"
        export MODELSCOPE_API_KEY="$(cat ${config.sops.secrets."modelscope/api-key".path})"
      '';
    in
    {
      sops.secrets = mylib.mkSopsSecrets enabledSecrets;
      programs.bash.initExtra = shellInit;
      programs.zsh.initContent = shellInit;
    }
  );
}
