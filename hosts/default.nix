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

  yuuko-k8s = {
    type = "nixos";
    system = "aarch64-linux";
    deploy = rootDeploy // {
      remoteBuild = true;
    };
    nixos-modules = [ ./k8s/yuuko-k8s ];
  };

  sakamoto-k8s = {
    type = "nixos";
    system = "aarch64-linux";
    deploy = rootDeploy // {
      remoteBuild = true;
    };
    nixos-modules = [ ./k8s/sakamoto-k8s ];
  };

  homelab-1 = {
    type = "nixos";
    system = "x86_64-linux";
    deploy = rootDeploy // {
      remoteBuild = true;
    };
    nixos-modules = [ ./k8s/homelab-1 ];
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
    deployDiff = false;
    darwin-modules = [ ./ling ];
    home-modules = [ ./ling/home.nix ];
  };

  router-mine = {
    type = "openwrt";
    uci-modules = [ ./router-mine ];
    firmware = import ./router-mine/firmware.nix;
  };
}
