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

# before run
# uninstall yabai and skhd;
echo "PROFILE=<hostname>" >> .env

# run 
just rebuild
just switch

```

## 常见问题

### font 文件 一直在等lock

解决：`sudo rm -rf /nix/store/**.lock`


