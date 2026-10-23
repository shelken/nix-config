brew bundle cleanup --file=$(nix path-info /run/current-system --recursive 2>/dev/null | grep Brewfile | head -1)
