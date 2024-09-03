{
  config,
  mylibx,
  ...
}: {
  programs = {
    gh = {
      enable = true;
    };
    bash.initExtra = ''
      export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
    '';
    zsh.initExtra = ''
      export GITHUB_TOKEN="$(cat ${config.sops.secrets."github/cli-token".path})"
    '';
  };

  sops.secrets = {
    "github/cli-token" = {
      sopsFile = mylibx.get-sops-file "shelken/default.yaml";
      path = "${config.home.homeDirectory}/.config/gh/access-token";
    };
  };
}
