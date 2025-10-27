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
  };

  programs.zsh = {
    enable = true;
    inherit envExtra;
  };

  home.shellAliases = {
    # idea = "open -a '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' ."; # 使用idea打开当前目录
    deq = "sudo xattr -r -d com.apple.quarantine";
  };

  # home.activation.AppHotKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
  #   # 1capture: `cmd+ctrl 2` screencapture
  #   # '{"carbonModifiers":4352,"carbonKeyCode":19}' | xxd -p | tr -d '\n'
  #   run /usr/bin/defaults write com.xunyong.1capture   com.onecapture.capture -data 7b22636172626f6e4d6f64696669657273223a343335322c22636172626f6e4b6579436f6465223a31397d
  #   # /usr/bin/defaults write com.xunyong.1capture   com.onecapture.capture -data 7b22636172626f6e4d6f64696669657273223a343335322c22636172626f6e4b6579436f6465223a32327d
  # '';
}
