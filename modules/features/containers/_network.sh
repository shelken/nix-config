# 网络只能复用或创建；参数变化不触发删除和重建。
if [[ $# != 2 || ( $1 != --check && $1 != --ensure ) ]]; then
  echo "Usage: vps-container-network --check|--ensure NETWORK_JSON" >&2
  exit 2
fi
mode=$1
source=$2

normalize() {
  jq -ceS '
    if .Name != "homelab" or .Driver != "bridge"
      or (.EnableIPv6 | type) != "boolean"
      or (.Internal | type) != "boolean"
      or (.Attachable | type) != "boolean"
      or (.IPAM.Driver | type) != "string"
      or (.IPAM.Config | type) != "array"
      or (.IPAM.Config | length) == 0
    then error("Unsupported network description") else . end
    | {
        Name, Driver, EnableIPv6, Internal, Attachable,
        Options: (.Options // {}),
        IPAM: {
          Driver: .IPAM.Driver,
          Options: (.IPAM.Options // {}),
          Config: (.IPAM.Config | map({
            Subnet,
            Gateway: (.Gateway // ""),
            IPRange: (.IPRange // ""),
            AuxiliaryAddresses: (.AuxiliaryAddresses // {})
          }) | sort_by(.Subnet))
        }
      }
  ' "$@"
}

expected=$(normalize "$source")
found=$(docker network ls --filter 'name=^homelab$' --format '{{.Name}}')
if [[ -z $found ]]; then
  if [[ $mode == --check ]]; then
    echo "homelab network is missing; stop before switching containers." >&2
    exit 1
  fi
  mapfile -t args < <(jq -r '
    ["--driver", .Driver, "--ipam-driver", .IPAM.Driver]
    + (if .EnableIPv6 then ["--ipv6"] else [] end)
    + (if .Internal then ["--internal"] else [] end)
    + (if .Attachable then ["--attachable"] else [] end)
    + [(.Options | to_entries[]) | "--opt", (.key + "=" + .value)]
    + [(.IPAM.Options | to_entries[]) | "--ipam-opt", (.key + "=" + .value)]
    + [(.IPAM.Config[]) |
        "--subnet", .Subnet,
        (if .Gateway != "" then "--gateway", .Gateway else empty end),
        (if .IPRange != "" then "--ip-range", .IPRange else empty end),
        ((.AuxiliaryAddresses | to_entries[]) | "--aux-address", (.key + "=" + .value))
      ]
    | .[]
  ' <<< "$expected")
  docker network create "${args[@]}" homelab >/dev/null
elif [[ $found != homelab ]]; then
  echo "Ambiguous homelab network selection." >&2
  exit 1
fi

actual=$(docker network inspect homelab | jq -ce '.[0]' | normalize)
if [[ $actual != "$expected" ]]; then
  echo "homelab network differs from the recorded configuration; no network was removed." >&2
  exit 1
fi
echo "homelab network matches the recorded configuration."
