{
  when = "0:00";
  user = true;
  script = ''
    # 每日零点自动执行 pi ping 测试
    PATH="$HOME/.cache/.bun/bin:$HOME/.local/bin:$PATH"
    pi --no-session --model openai-codex/gpt-5.6-luna --thinking off -nc --no-skills --no-extensions -p "hi"
  '';
}
