{
  username,
  disko,
  niri,
  lib,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # disko
    disko.nixosModules.default
    ../disko-config/general.nix
  ];

  services.sunshine.enable = true;

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
      devices = ["/dev/sda"];
      enable = true;
      efiSupport = true;
      useOSProber = true;
      efiInstallAsRemovable = true;
    };
  };

  networking = {
    hostName = "nixos-arm-test-1";
    wireless.enable = false; # Enables wireless support via wpa_supplicant.

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    networkmanager.enable = true;

    enableIPv6 = false; # disable ipv6
    interfaces.enp0s5 = {
      useDHCP = true;
      # ipv4.addresses = [
      #   {
      #     address = "192.168.6.155";
      #     prefixLength = 24;
      #   }
      # ];
    };
    # defaultGateway = "192.168.6.1";
    # nameservers = [
    #   "119.29.29.29" # DNSPod
    #   "223.5.5.5" # AliDNS
    # ];
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
