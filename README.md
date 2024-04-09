# darwin

## 初始化

```bash
# 1. install homebrew 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. install nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 3. clone repo
git clone https://github.com/shelken/nix-config.git ~/nix-config && cd ~/nix-config

# 4. uninstall yabai and skhd;(if you have installed)

# 5. specify the profile that defined in flake.nix 
echo "PROFILE=<profile-name>" >> .env

```

## 应用

```bash

# before run, you should have just. `brew install just`
# switch  
just switch

# only build result
just b

```

## 卸载

```bash

# uninstall nix 
/nix/nix-installer uninstall

```


## 常见问题

### font 文件 一直在等lock

解决：`sudo rm -rf /nix/store/**.lock`

# 部署

> 在本地部署其他机器

## example

```bash
# 1 deploy pve156 config on host(pve156) 
just deploy pve156 shelken@pve156 
# 2
just deploy pve156 shelken@192.168.6.156 
```
