{
  config,
  lib,
  pkgs,
  ...
}:
let
  palette = lib.mapAttrs (_: color: color.hex) (
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${config.catppuccin.flavor}.colors
  );
  accent = palette.${config.catppuccin.accent};
in
{
  home.file.".pi/agent/themes/catppuccin.json".source =
    (pkgs.formats.json { }).generate "pi-theme.json"
      {
        name = "catppuccin";
        colors = {
          inherit accent;
          border = palette.blue;
          borderAccent = accent;
          borderMuted = palette.surface0;
          success = palette.green;
          error = palette.red;
          warning = palette.yellow;
          muted = palette.overlay1;
          dim = palette.overlay0;
          inherit (palette) text;
          thinkingText = palette.overlay1;

          selectedBg = palette.surface0;
          userMessageBg = palette.surface0;
          userMessageText = palette.text;
          customMessageBg = palette.surface1;
          customMessageText = palette.text;
          customMessageLabel = accent;
          toolPendingBg = palette.mantle;
          toolSuccessBg = "#3e4b4c";
          toolErrorBg = "#4c3a4c";
          toolTitle = palette.text;
          toolOutput = palette.subtext0;

          mdHeading = palette.peach;
          mdLink = palette.blue;
          mdLinkUrl = palette.overlay0;
          mdCode = palette.teal;
          mdCodeBlock = palette.green;
          mdCodeBlockBorder = palette.overlay1;
          mdQuote = palette.subtext0;
          mdQuoteBorder = palette.overlay1;
          mdHr = palette.overlay1;
          mdListBullet = accent;

          toolDiffAdded = palette.green;
          toolDiffRemoved = palette.red;
          toolDiffContext = palette.overlay1;

          syntaxComment = palette.overlay0;
          syntaxKeyword = palette.mauve;
          syntaxFunction = palette.blue;
          syntaxVariable = palette.text;
          syntaxString = palette.green;
          syntaxNumber = palette.peach;
          syntaxType = palette.yellow;
          syntaxOperator = palette.sky;
          syntaxPunctuation = palette.overlay2;

          thinkingOff = palette.surface0;
          thinkingMinimal = palette.overlay0;
          thinkingLow = palette.blue;
          thinkingMedium = palette.sapphire;
          thinkingHigh = palette.mauve;
          thinkingXhigh = palette.pink;

          bashMode = palette.green;
        };
        export = {
          pageBg = palette.crust;
          cardBg = palette.mantle;
          infoBg = palette.surface0;
        };
      };
}
