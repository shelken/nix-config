{
  myvars,
  pkgs,
  ...
}: {
  home.homeDirectory = "/Users/${myvars.username}";
  home.packages = with pkgs; [
    gh
    gh-dash
    glab
    nali
    rclone
    superfile
  ];
}
