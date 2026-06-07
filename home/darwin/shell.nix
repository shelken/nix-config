{ ... }:
let
  envExtra = ''
    export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  '';
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

  home.shellAliases = {
    # idea = "open -a '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' ."; # 使用idea打开当前目录
    deq = "sudo xattr -r -d com.apple.quarantine";
  };

}
