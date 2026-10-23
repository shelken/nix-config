# NTFS 磁盘读写工具（Mounty, ntfs-3g, macfuse，可选）
{ ... }:
{
  flake.modules.darwin.ntfs.homebrew.casks = [
    "mounty"
    "ntfs-3g-mac"
    "macfuse"
  ];
}
