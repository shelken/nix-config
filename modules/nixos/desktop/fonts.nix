{pkgs, ...}: {
  fonts = {
    # use fonts specified by user rather than default ones
    # enableDefaultPackages = false;
    # fontDir.enable = true;

    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    # fontconfig.defaultFonts = {
    #   serif = ["Source Han Serif SC" "Source Han Serif TC" "Noto Color Emoji"];
    #   sansSerif = ["Source Han Sans SC" "Source Han Sans TC" "Noto Color Emoji"];
    #   monospace = ["JetBrainsMono Nerd Font" "Noto Color Emoji"];
    #   emoji = ["Noto Color Emoji"];
    # };
  };
}
