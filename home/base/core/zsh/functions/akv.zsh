# 用于 az 自己homelab-vault调用
#

az keyvault secret show --vault-name shelken-homelab \
    --name "$1" --query value -o tsv
