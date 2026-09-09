{ pkgs, secretPath, ... }:
{
  when = [
    "0:00"
    "12:00"
  ];
  user = true;
  packages = with pkgs; [
    bun
    git
    just
    openssh
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
    if [ ! -f "$REPO/node_modules/.bin/ccusage" ]; then
      bun install --cwd "$REPO" --frozen-lockfile 2>/dev/null || bun install --cwd "$REPO"
    fi


    just -f "$REPO/justfile" -d "$REPO" sync-push
  '';
}
