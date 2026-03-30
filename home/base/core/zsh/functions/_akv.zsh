#compdef akv

# _akv - akv 命令的 zsh 补全函数
# 按 Tab 时自动从 shelken-homelab vault 拉取 secret 名称列表

local vault_name="shelken-homelab"
local -a secrets
local state

_arguments \
  '(-l --list)'{-l,--list}'[列出所有 secret 名称]' \
  '(-h --help)'{-h,--help}'[显示帮助信息]' \
  '1:secret 名称:->secret'

case $state in
  secret)
    secrets=(${(f)"$(az keyvault secret list \
      --vault-name "$vault_name" \
      --query "[].name" \
      -o tsv 2>/dev/null)"})
    _describe 'secret 名称' secrets
    ;;
esac
