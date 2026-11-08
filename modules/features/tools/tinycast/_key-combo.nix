# 把 "alt-f"、"alt-shift-enter" 这类快捷键转成 Tinycast 用的 Carbon 键码与修饰键掩码 JSON
{ lib }:
str:
let
  keyMap = {
    a = 0;
    s = 1;
    d = 2;
    f = 3;
    h = 4;
    g = 5;
    z = 6;
    x = 7;
    c = 8;
    v = 9;
    b = 11;
    q = 12;
    w = 13;
    e = 14;
    r = 15;
    y = 16;
    t = 17;
    "1" = 18;
    "2" = 19;
    "3" = 20;
    "4" = 21;
    "6" = 22;
    "5" = 23;
    "=" = 24;
    "9" = 25;
    "7" = 26;
    "-" = 27;
    "8" = 28;
    "0" = 29;
    "]" = 30;
    o = 31;
    u = 32;
    "[" = 33;
    i = 34;
    p = 35;
    l = 37;
    j = 38;
    "'" = 39;
    k = 40;
    ";" = 41;
    "\\" = 42;
    "," = 43;
    "/" = 44;
    n = 45;
    m = 46;
    "." = 47;
    "`" = 50;
    return = 36;
    enter = 36;
    tab = 48;
    space = 49;
    delete = 51;
    backspace = 51;
    escape = 53;
    esc = 53;
    left = 123;
    right = 124;
    down = 125;
    up = 126;
    f1 = 122;
    f2 = 120;
    f3 = 99;
    f4 = 118;
    f5 = 96;
    f6 = 97;
    f7 = 98;
    f8 = 100;
    f9 = 101;
    f10 = 109;
    f11 = 103;
    f12 = 111;
  };
  modMap = {
    cmd = 256;
    command = 256;
    shift = 512;
    alt = 2048;
    opt = 2048;
    option = 2048;
    ctrl = 4096;
    control = 4096;
  };
  normalized = builtins.replaceStrings [ "+" " " ] [ "-" "" ] (lib.toLower str);
  tokens = builtins.filter (x: builtins.isString x && x != "") (builtins.split "-" normalized);
  len = builtins.length tokens;
  key = builtins.elemAt tokens (len - 1);
  mods = builtins.genList (i: builtins.elemAt tokens i) (len - 1);
  keyCode = keyMap.${key} or (throw "darwinKeyCombo: 未知按键名 '${key}' (位于快捷键 '${str}')");
  modifiers = builtins.foldl' (
    acc: m: acc + (modMap.${m} or (throw "darwinKeyCombo: 未知修饰键 '${m}' (位于快捷键 '${str}')"))
  ) 0 mods;
in
builtins.toJSON {
  combo._0 = {
    carbonKeyCode = keyCode;
    carbonModifiers = modifiers;
  };
}
