{ self }:
let
  rootDeploy = {
    sshUser = "root";
    interactiveSudo = false;
  };
in
{
  vps-cc = {
    type = "nixos";
    system = "x86_64-linux";
    deploy = rootDeploy // {
      remoteBuild = true;
    };
    nixos-modules = [ ./vps/vps-cc ];
  };

  hk1box = {
    type = "nixos";
    system = "aarch64-linux";
    deploy = rootDeploy // {
      remoteBuild = true;
    };
    nixos-modules = [ ./hk1box ];
  };

  vps-test = {
    type = "nixos";
    system = "x86_64-linux";
    deploy = rootDeploy;
    nixos-modules = [ ./vm/vps-test ];
  };

  lima-test = {
    type = "nixos";
    system = "aarch64-linux";
    nixos-modules = [ ./vm/lima-test ];
  };

  work-test = {
    type = "nixos";
    system = "x86_64-linux";
    # 不建 hosts 目录：calcUniformSchedule 按 hosts/ 目录数排定备份时段
    nixos-modules = [ self.modules.nixos.tui ];
  };

  yuuko = {
    type = "darwin";
    system = "aarch64-darwin";
    deploy = { };
    darwin-modules = [ ./yuuko ];
    home-modules = [ ./yuuko/home.nix ];
  };

  sakamoto = {
    type = "darwin";
    system = "aarch64-darwin";
    deploy = { };
    darwin-modules = [ ./sakamoto ];
    home-modules = [ ./sakamoto/home.nix ];
  };

  mio = {
    type = "darwin";
    system = "aarch64-darwin";
    darwin-modules = [ ./mio ];
    home-modules = [ ./mio/home.nix ];
  };

  ling = {
    type = "darwin";
    system = "aarch64-darwin";
    deploy = { };
    darwin-modules = [ ./ling ];
    home-modules = [ ./ling/home.nix ];
  };
}
