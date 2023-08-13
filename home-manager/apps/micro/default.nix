{
  home.file.".config/micro/bindings.json".source = ./bindings.json;
  programs.micro = {
    enable = true;
    settings = {
      "*.nix" = {
        "filetype" = "nix";
      };
      colorscheme = "monokai";
      mkparents = true;
      softwrap = true;
      tabmovement = true;
      tabsize = 2;
      tabstospaces = true;
      autosu = true;
    };
  };
}
