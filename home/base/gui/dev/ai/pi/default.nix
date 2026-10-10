{
  pkgs,
  config,
  lib,
  mylib,
  ...
}:
let
  linkPi = rel: mylib.mkConfigFile config "home/base/gui/dev/ai/pi/${rel}";
  linkPiConfig = rel: mylib.mkConfigFile config "home/base/gui/dev/ai/pi/configs/${rel}";
  jsonFormat = pkgs.formats.json { };
  readYaml =
    file:
    builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "converted-models.json" { } ''
          ${pkgs.yj}/bin/yj < ${file} > $out
        ''
      )
    );

  sharedModels = readYaml ../omp/models.yml;
  piModels = readYaml ./models.yml;
  mergedModels = lib.recursiveUpdate sharedModels piModels;

  adaptModel =
    model:
    let
      efforts = if model ? thinking then model.thinking.efforts or [ ] else [ ];
      effortMap = model.reasoningEffortMap or { };
    in
    builtins.removeAttrs model [
      "thinking"
      "reasoningEffortMap"
    ]
    // lib.optionalAttrs (efforts != [ ]) {
      thinkingLevelMap = lib.genAttrs efforts (level: effortMap.${level} or level);
    };

  adaptProvider =
    provider:
    let
      apiKey = provider.apiKey or null;
    in
    builtins.removeAttrs provider [ "discovery" ]
    // lib.optionalAttrs (provider ? apiKey && builtins.match "^[A-Z][A-Z0-9_]*$" apiKey != null) {
      apiKey = "${"$"}${apiKey}";
    }
    // lib.optionalAttrs (provider ? models) {
      models = map adaptModel provider.models;
    }
    // lib.optionalAttrs (provider ? modelOverrides) {
      modelOverrides = lib.mapAttrs (_: adaptModel) provider.modelOverrides;
    };

  generatedModels = jsonFormat.generate "pi-models.json" {
    providers = lib.mapAttrs (_: adaptProvider) mergedModels.providers;
  };

  shellInit = ''
    export POWERLINE_NERD_FONTS=1
    export FFF_ENABLE_HOME_SCAN=0
    export ANTIGRAVITY_NO_EXTRA_TOOLS=1
  '';
in
{
  home.packages = [ pkgs.mermaid-cli ];

  home.sessionVariables = {
    ANTIGRAVITY_NO_EXTRA_TOOLS = "1";
  };
  home.shellAliases.pi = "sec-run pi";

  programs.mise.globalConfig.tools."npm:@earendil-works/pi-coding-agent" = {
    version = "latest";
    minimum_release_age = "0h";
  };

  home.file = {
    ".pi/agent/settings.json" = linkPi "settings.json";
    ".pi/agent/keybindings.json" = linkPi "keybindings.json";
    ".pi/agent/models.json" = {
      source = generatedModels;
      force = true;
    };
    ".pi/agent/permissions.yaml" =
      mylib.mkConfigFile config "home/base/gui/dev/ai/omp/permissions.yaml";

    ".pi/agent/caveman.json" = linkPiConfig "caveman.json";
    ".pi/agent/context-prune/settings.json" = linkPiConfig "context-prune.json";
    ".pi/agent/extensions/pi-recap.json" = linkPiConfig "pi-recap.json";
    ".pi/agent/extensions/pi-rename.json" = linkPiConfig "pi-rename.json";
    ".pi/agent/extensions/pi-vision-handoff.json" = linkPiConfig "pi-vision-handoff.json";
    ".pi/agent/extensions/trae/config.json" = linkPiConfig "trae.json";
    ".pi/agent/extensions/subdir-context.ts" =
      mylib.mkConfigFile config "home/base/gui/dev/ai/omp/extensions/subdir-context.ts";
  };

  programs.zsh.initContent = shellInit;

  shelken.backup.app.pi = [
    "${config.home.homeDirectory}/.pi/agent/sessions"
  ];
}
