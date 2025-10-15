{
  ...
}:
let
in
{
  #TODO 配置
  programs.bash.initExtra = ''
    eval "$(codex completion bash)"
  '';
  programs.zsh.initContent = ''
    eval "$(codex completion zsh)"
  '';
}
