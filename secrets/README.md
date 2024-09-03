# secrets

## sops

> [repo](https://github.com/Mic92/sops-nix)

> 以下参考[来源](https://github.com/Mic92/sops-nix?tab=readme-ov-file#usage-example)

> sops 的 secrets 存储在我的私人仓库中[secrets.nix](https://github.com/shelken/secrets.nix)

```nix

# 引入sops-nix

sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# 使用home-manager 模块
imports = [
  # sops-nix
  sops-nix.homeManagerModules.sops
]

# 配置

sops.age = {
  generateKey = true;
  keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  sshKeyPaths = [
    "${config.home.homeDirectory}/.ssh/id_ed25519"
  ];
};
home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;

```

然后生成一个密钥用于编辑secrets

```shell

# for age..
$ mkdir -p ~/.config/sops/age
$ age-keygen -o ~/.config/sops/age/keys.txt
# or to convert an ssh ed25519 key to an age key
$ mkdir -p ~/.config/sops/age
$ nix run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt

```

然后根据用户或者机器的公钥生成一个age公钥

```shell

# 如果已经有了上一个的密钥，可以根据上一步的密钥反推公钥
age-keygen -y ~/.config/sops/age/keys.txt

# 或者
nix run nixpkgs#ssh-to-age -- < ~/.ssh/id_ed25519.pub

```

将生成的age公钥放入`.sops.yaml`中，根据`creation_rules`来配置哪些公钥读取哪些secrets

每次编辑secrets时，使用命令`sops xxx/xxx.yaml`

使用时调用`mylibx.get-sops-file`获取来自`secrets.nix`的secrets
