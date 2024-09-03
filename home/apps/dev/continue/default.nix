{
  mylibx,
  myvars,
  ...
}: let
in {
  # home.file.".continue/config.json".source = ./config.json;
  sops.secrets = {
    "deepseek/api-key" = {
      # path = "${config.home.homeDirectory}/test2.txt";
      # sopsFile = ../../../../sops/secrets/deepseek/default.yaml;
      sopsFile = mylibx.get-sops-file "${myvars.username}/default.yaml";
    };
  };

  # sops.templates."continue/config.json".content = ''
  #   {
  #     "test": "${config.sops.placeholder."deepseek/api-key"}"
  #   }
  # '';
  # home.file."test3.json".source = config.sops.templates."continue/config.json".path;
}
