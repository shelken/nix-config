{lib, ...}:
{
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
  relativeToRoot = lib.path.append ../.;
}
