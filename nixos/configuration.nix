# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      #<home-manager/nixos>
    ];

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n.defaultLocale = "zh_CN.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.shelken = {
    isNormalUser = true;
    description = "shelken";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
    	"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDbh2iFUarY/uqhy4tsGCw9g/coqcSPNmPzsX92OgXx1z2//DK3fLM3K1q/yHRBTGw0MhILIie4R48yUHHnZZ4DJiO8Y/YY/HfgNOMb/VNpJo6M1NTAxBGxKACTWAQME8M0T+IMMakOkbXlV/z/Wo4+NHOTlaGURqRDtAwFbv7vB9kN8TvPLcXZHP/OP4gdvKsTi3j3h+mpRlFo+aFuvYCmNioHcpL7Y2sEe9AMnYZGeTkaoqTxwuh/qdgiRgnkKW2X1Sgpw4+23677u5lsYpTJQ1MVMSj6ofJqdpv9IYBtXVCxhrp8geYm9/qX5kMrDBVDWkV+sn7KbzUtsoRYzTYFEPI7dfp3XtlTw8+CKteXLXvaHLwZn3cDBaC7AQ5iXNJWfL5p7ZzWxtMAX7AHetevVXwL7ikBu2UWYU7vT9L6dzXwAxVRIqyVxQFIvBNJggCp8vSrK3+Z19Lq7A0GZD2EoM72XaSO+iLw2DRwK8ZGeqFUTD477oFCVMOWJpaPw4E="	
    ];
  };

  environment.shells = with pkgs; [ zsh ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    #micro
    git
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

  services.openssh = {
  	enable = true;
	  settings.PasswordAuthentication = false;
  };
  services.qemuGuest.enable = true; 
  # 
  virtualisation.docker.enable = true;
  # sudo免密码
  security.sudo.extraRules= [
    {
      users = [ "shelken" ];
      commands = [
        { command = "ALL" ;
          options= [ "NOPASSWD" ];
        }
      ];
    }
  ];


  programs.zsh.enable = true;

  # 开启flakes 命令
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # home-manager配置

  #home-manager = {
  #  useGlobalPkgs = true;
  #  useUserPackages = true;
  #  users.shelken = import ./home.nix;
  #};

 
  
}
