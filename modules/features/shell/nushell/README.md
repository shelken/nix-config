# nushell

日常交互 shell，从 zsh 里敲 `nu` 进入，环境（PATH、工具变量、XDG 目录）继承自 zsh；登录 shell 与 `$SHELL` 仍是 zsh，避免影响 ssh 远程命令、VS Code Remote 等依赖 POSIX 登录 shell 的场景

zsh 函数 `proxy` 与 `unproxy` 暂未移植，需要时临时切回 zsh
