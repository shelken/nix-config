{ pkgs, secretPath, ... }:
{
  when = [
    "0:00"
    "12:00"
  ];
  user = true;
  packages = with pkgs; [
    ccusage
    git
    just
    python3
  ];
  secrets = {
    GH_TOKEN = secretPath "github/cli-token";
    GITHUB_TOKEN = secretPath "github/cli-token";
  };
  script = ''
    REPO="$HOME/Code/active/shelken"
    if [ ! -d "$REPO/.git" ]; then
      echo "Profile repository $REPO not found, skipping."
      exit 0
    fi

    just -f "$REPO/justfile" -d "$REPO" sync-push
  '';
}
