#!/usr/bin/env bash
set -euo pipefail
umask 022

die() { echo "openwrt-imagebuild: $*" >&2; exit 1; }

work=""
part=""
cleanup() {
  [[ -n $part ]] && rm -f "$part"
  [[ -n $work ]] && rm -rf "$work"
}
trap cleanup EXIT

input=$(cat)
request=$(jq '.request' <<<"$input")
version=$(jq -r '.request.version' <<<"$input")
target=$(jq -r '.request.target' <<<"$input")
profile=$(jq -r '.request.profile' <<<"$input")
packages=$(jq -r '.request.packages | join(" ")' <<<"$input")
tarball=$(jq -r '.imagebuilder.tarball' <<<"$input")
tarball_url=$(jq -r '.imagebuilder.url' <<<"$input")
sums_url=$(jq -r '.imagebuilder.sha256sumsUrl' <<<"$input")

req_hash=$(jq -cS . <<<"$request" | sha256sum | cut -c1-12)
cache_root=/var/cache/openwrt-imagebuilder
tarball_path="$cache_root/tarballs/$tarball"
dl_dir="$cache_root/dl/$version/${target//\//-}"
out_dir="$cache_root/out/$req_hash"

mkdir -p "$cache_root/tarballs" "$dl_dir"

if [[ ! -f $tarball_path ]]; then
  echo "openwrt-imagebuild: 下载 $tarball" >&2
  sums=$(curl -fsSL "$sums_url")
  expected_sha=$(awk -v f="*$tarball" '$2 == f {print $1; exit}' <<<"$sums")
  [[ -n $expected_sha ]] || die "sha256sums 中未找到 $tarball"

  part="$tarball_path.part"
  curl -fL --progress-bar -o "$part" "$tarball_url" >&2
  actual_sha=$(sha256sum "$part" | awk '{print $1}')
  [[ $actual_sha == "$expected_sha" ]] || die "tarball sha256 不符"
  mv -f "$part" "$tarball_path"
  part=""
fi

find "$dl_dir" -maxdepth 1 -type f ! -name '*.apk' -delete

work=$(mktemp -d)

echo "openwrt-imagebuild: 解压 ImageBuilder" >&2
tar --zstd -xf "$tarball_path" --strip-components=1 -C "$work"
rm -rf "$work/dl"
ln -s "$dl_dir" "$work/dl"

rm -rf "$out_dir"
mkdir -p "$out_dir"

echo "openwrt-imagebuild: 构建 $profile ($version, $req_hash)" >&2
make -C "$work" image \
  PROFILE="$profile" \
  PACKAGES="$packages" \
  EXTRA_IMAGE_NAME="$req_hash" \
  BIN_DIR="$out_dir" >&2

manifest_raw=$(make -C "$work" --no-print-directory manifest \
  PROFILE="$profile" \
  PACKAGES="$packages" \
  STRIP_ABI=1)
manifest_json=$(jq -Rn '
  [inputs | select(length > 0) | split(" - ") | select(length == 2) | {key: .[0], value: .[1]}]
  | sort_by(.key)
  | from_entries
' <<<"$manifest_raw")

result=$(jq \
  --argjson req "$request" \
  --arg profile "$profile" \
  --argjson manifest "$manifest_json" '
  (.profiles[$profile].images[] | select(.type == "sysupgrade")) as $img
  | {
      request: $req,
      version_code: .version_code,
      image: { name: $img.name, sha256: $img.sha256 },
      manifest: $manifest
    }
' "$out_dir/profiles.json")

image_name=$(jq -r '.image.name' <<<"$result")
jq -n --argjson result "$result" --arg remote_image "$out_dir/$image_name" '{
  result: $result,
  remote_image: $remote_image
}'
