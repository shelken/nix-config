# darwin

## 初始化

```bash
# install homebrew 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# install nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# uninstall nix 
/nix/nix-installer uninstall

# clone repo
git clone https://github.com/shelken/my-nix-flake.git ~/my-nix-flake

# run 
nix build $config_target --extra-experimental-features "nix-command flakes"

```
