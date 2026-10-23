# akv - 查询 shelken-homelab Azure Key Vault 中的 secret
# Usage:
#   akv <secret-name>       获取指定 secret 的值
#   akv --list | -l         列出所有 secret 名称
#   akv --help | -h         显示帮助

local vault_name="shelken-homelab"

case "$1" in
--help | -h | '')
    echo "Usage:"
    echo "  akv <secret-name>    获取指定 secret 的值"
    echo "  akv --list|-l        列出所有 secret 名称"
    echo "  akv --help|-h        显示帮助"
    [[ -z "$1" ]] && return 1 || return 0
    ;;
--list | -l)
    az keyvault secret list \
        --vault-name "$vault_name" \
        --query "[].name" \
        -o tsv
    ;;
*)
    az keyvault secret show \
        --vault-name "$vault_name" \
        --name "$1" \
        --query value \
        -o tsv
    ;;
esac
