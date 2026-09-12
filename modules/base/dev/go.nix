{
  mylib,
  ...
}:
{
  options.shelken.dev.go.enable = mylib.mkBoolOpt false "Whether or not use.";

  config.shelken.internal.homeModules = [
    (
      {
        config,
        lib,
        osConfig,
        pkgs,
        ...
      }:
      let
        cfg = osConfig.shelken.dev.go;
      in
      {
        config = lib.mkIf cfg.enable {
          home.sessionVariables = {
            # for go
            # GOPROXY = "https://goproxy.io";
          };

          home.packages = with pkgs; [
            #-- golang
            go
          ];

          # for go goPath
          programs.go = {
            enable = true;
            env = {
              GOPATH = [
                "${config.home.homeDirectory}/go"
              ];
            };
          };
        };
      }
    )
  ];
}
