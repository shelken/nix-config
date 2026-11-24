{ pkgs, secretPath, ... }:
{
  when = [
    "0:04"
    "12:04"
  ];
  packages = with pkgs; [
    git
    mise
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

    cd "$REPO"
    if [ ! -d "$REPO/node_modules" ]; then
      mise exec -- bun install --frozen-lockfile 2>/dev/null || mise exec -- bun install
    fi

    mise exec -- just sync-push
  '';
}
