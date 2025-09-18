{pkgs, ...}: {
  imports = [
    # 特定应用
    # ../../apps/squirrel
    ../../apps/kitty
  ];

  home.packages = with pkgs; [
    kitty
  ];
}
