{username, ...}:
#############################################################
#
#  PVE 155
#
#############################################################
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    ../../modules/nixos/core-server.nix

    ../../modules/desktop
  ];

  #nixpkgs.overlays = import ../../../overlays args;

  # Enable binfmt emulation of aarch64-linux, this is required for cross compilation.
  #boot.binfmt.emulatedSystems = ["aarch64-linux" "riscv64-linux"];
  # supported fil systems, so we can mount any removable disks with these filesystems
  boot.supportedFilesystems = [
    "ext4"
    "btrfs"
    "xfs"
    #"zfs"
    "ntfs"
    "fat"
    "vfat"
    "exfat"
    "cifs" # mount windows share
  ];

  # Bootloader.
  boot.loader = {
    #efi = {
    #  canTouchEfiVariables = true;
    #  efiSysMountPoint = "/boot/efi"; # ← use the same mount point here.
    #};
    #systemd-boot.enable = true;
    grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
    };
  };

  networking = {
    hostName = "pve155";
    wireless.enable = false; # Enables wireless support via wpa_supplicant.

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    networkmanager.enable = true;

    enableIPv6 = false; # disable ipv6
    interfaces.ens18 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.6.155";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "192.168.6.1";
    nameservers = [
      "119.29.29.29" # DNSPod
      "223.5.5.5" # AliDNS
    ];
  };

  security.sudo.extraRules = [
    {
      users = [username];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  #virtualisation.docker.storageDriver = "btrfs";

  ## for Nvidia GPU
  #services.xserver.videoDrivers = ["nvidia"]; # will install nvidia-vaapi-driver by default
  #hardware.nvidia = {
  #  # Optionally, you may need to select the appropriate driver version for your specific GPU.
  #  package = config.boot.kernelPackages.nvidiaPackages.stable;

  #  # Modesetting is needed for most Wayland compositors
  #  modesetting.enable = true;
  #  # Use the open source version of the kernel module
  #  # Only available on driver 515.43.04+
  #  open = false;

  #  powerManagement.enable = true;
  #};
  #virtualisation.docker.enableNvidia = true; # for nvidia-docker

  #hardware.opengl = {
  #  enable = true;
  #  # if hardware.opengl.driSupport is enabled, mesa is installed and provides Vulkan for supported hardware.
  #  driSupport = true;
  #  # needed by nvidia-docker
  #  driSupport32Bit = true;
  #};

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
