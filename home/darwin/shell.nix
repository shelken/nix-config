{ pkgs, ... }:
let
  envExtra = ''
    export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  '';
  # ali-rantakari/trash：系统 API → Finder 废纸篓；静默接受 rm 的 -rf 等 flag
  # 用绝对路径，避免和 macOS 15+ 自带 /usr/bin/trash 撞名
  macTrash = "${pkgs.darwin.trash}/bin/trash";
in
{
  # Homebrew's default install location:
  #   /opt/homebrew for Apple Silicon
  #   /usr/local for macOS Intel
  # The prefix /opt/homebrew was chosen to allow installations
  # in /opt/homebrew for Apple Silicon and /usr/local for Rosetta 2 to coexist and use bottles.
  programs.bash = {
    enable = true;
    bashrcExtra = envExtra;
    profileExtra = ''
      source ~/.orbstack/shell/init.bash 2>/dev/null || true
    '';
  };

  programs.zsh = {
    enable = true;
    inherit envExtra;
    profileExtra = ''
      source ~/.orbstack/shell/init.zsh 2>/dev/null || true
    '';
  };

  home.packages = [ pkgs.darwin.trash ];

  home.shellAliases = {
    # idea = "open -a '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' ."; # 使用idea打开当前目录
    deq = "sudo xattr -r -d com.apple.quarantine";
    rm = macTrash;
  };

}
