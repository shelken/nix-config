# 鼠须管配色：从 catppuccin 调色板生成，flavor 与 accent 跟随 vars
{
  config,
  lib,
  myvars,
}:
let
  palette = lib.mapAttrs (_: color: color.hex) (
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${config.catppuccin.flavor}.colors
  );
  accent = palette.${config.catppuccin.accent};

  # rime 的颜色是 0xBBGGRR，与 CSS 的 #RRGGBB 字节顺序相反
  bgr =
    hex:
    let
      part = start: builtins.substring start 2 hex;
    in
    "0x${lib.toUpper (part 5 + part 3 + part 1)}";
in
''
  patch:
    preset_color_schemes/catppuccin:
      name: ${myvars.catppuccin.displayName}
      translucency: true
      mutual_exclusive: false
      shadow_size: 0
      line_spacing: 5
      alpha: 1
      spacing: 10

      back_color: ${bgr palette.crust}
      border_color: ${bgr palette.mantle}
      text_color: ${bgr palette.subtext1}
      label_color: ${bgr palette.subtext0}
      candidate_text_color: ${bgr palette.text}
      hilited_back_color: ${bgr accent}
      hilited_candidate_text_color: ${bgr palette.base}
      hilited_candidate_label_color: ${bgr palette.surface0}
      hilited_text_color: ${bgr palette.green}
      hilited_comment_text_color: ${bgr palette.surface0}
      comment_text_color: ${bgr palette.green}
''
