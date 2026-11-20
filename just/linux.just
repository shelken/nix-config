set working-directory := '..'
set positional-arguments := true

# 生成镜像（变体由 nixpkgs 提供：iso / iso-installer / qemu / proxmox / sd-card …）
gen-image host format:
    @{{ justfile_directory() }}/utils/script/just/gen-image "$@"

# 查看包文件树
qip:
    @nix-store --gc --print-roots | rg -v '/proc/' | rg -Po '(?<= -> ).*' | xargs -o nix-tree

# 清除历史；默认`3d`; 三天前
wipe duration="3d":
    @sudo nix profile wipe-history --older-than {{ duration }} --profile /nix/var/nix/profiles/system
