{ pkgs, ... }:
{
  every = 18000; # 5h
  packages = [
    pkgs.nodejs
    pkgs.mise
  ];
  script = ''
    # 当前没有注入任何key,因此选择的模型必须是oauth登录方式否则错误
    # pi --no-session --model openai/gpt-5.6-luna --thinking off -nc --no-skills --no-extensions -p "hi"
    mise exec -- omp \
    --no-session \
    --no-tools \
    --no-extensions \
    --system-prompt ' ' \
    --model openai-codex/gpt-5.6-luna \
    --thinking low \
    --cwd /tmp \
    -p "hi" \
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
