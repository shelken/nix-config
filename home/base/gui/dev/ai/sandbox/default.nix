{
  config,
  lib,
  mylib,
  pkgs,
  llm-agents,
  extendModules,
  ...
}:
let
  msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
  msbConfig = (pkgs.formats.json { }).generate "microsandbox-config.json" {
    version = 1;
    home = msbHome;
    paths.cache = "${config.home.homeDirectory}/.cache/microsandbox";
  };

  # Guest 不跟随宿主 live-edit 软链，避免绕过只读挂载
  fileConfig =
    if config.shelken.dotfiles.liveEdit then
      (extendModules {
        modules = [ { shelken.dotfiles.liveEdit = lib.mkForce false; } ];
      }).config
    else
      config;

  configFiles = lib.filterAttrs (
    _: file:
    file.enable && (lib.hasPrefix ".omp/agent/" file.target || lib.hasPrefix ".agents/" file.target)
  ) fileConfig.home.file;

  models = pkgs.runCommand "omp-sandbox-models.yml" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
    yq '(.. | select(tag == "!!map") | select(has("baseUrl")) | .baseUrl) |= sub("^(https?://)(127[.]0[.]0[.]1|localhost|\\[::1\\])([:/]|$)", "''${1}host.microsandbox.internal''${3}")' ${../omp/models.yml} > "$out"
  '';

  sandboxConfig = pkgs.linkFarm "sandbox-config" (
    lib.mapAttrsToList (_: file: {
      name = file.target;
      path = if file.target == ".omp/agent/models.yml" then models else file.source;
    }) configFiles
  );

  gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
    user = config.programs.git.settings.user;
    credential."https://github.com".helper = "!gh auth git-credential";
    url."https://github.com/".insteadOf = "git@github.com:";
  };

  linuxSystem = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
  sandbox = import ./wrapper.nix {
    inherit
      pkgs
      gitConfig
      msbConfig
      msbHome
      ;
    linuxPkgs = llm-agents.inputs.nixpkgs.legacyPackages.${linuxSystem};
    inherit (llm-agents.packages.${linuxSystem}) omp;
    name = "sb-default";
    conf = ./sb-default.yaml;
  };
in
{
  options.shelken.dev.ai.sandbox.enable =
    mylib.mkBoolOpt false "Whether to install the agent sandbox.";

  config = lib.mkIf (config.shelken.dev.ai.enable && config.shelken.dev.ai.sandbox.enable) {
    programs.mise.globalConfig.tools.microsandbox = "0.7.7";

    home.sessionVariables = {
      MSB_HOME = msbHome;
      MSB_CONFIG_PATH = "${msbConfig}";
    };
    home.file.".config/sandbox/current".source = sandboxConfig;

    home.packages = [ sandbox ];
  };
}
