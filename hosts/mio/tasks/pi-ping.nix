{ pkgs, ... }:
{
  every = 3600 * 5 + 1; # 5小时1秒
  packages = [
    pkgs.nodejs
    pkgs.mise
  ];
  # omp 的 mp provider 按变量名取 key；缺失时会把变量名当字面量发出去
  secrets.MAGPIE_API_KEY = "op://Agent/MAGPIE_API_KEY/credential";
  script = ''
    mise exec -- omp \
    --no-session \
    --no-tools \
    --no-extensions \
    --system-prompt ' ' \
    --model mp/codex/gpt-6-luna \
    --thinking low \
    --cwd /tmp \
    -p "say hi" \
    --config <(cat <<'EOF'
    disabledProviders:
      - native
      - claude
      - agents
      - codex
      - gemini
      - opencode
      - github
      - agents-md
    EOF
    )
  '';
}
