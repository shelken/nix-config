# nushell

日常交互 shell，从 zsh 里敲 `nu` 进入，环境（PATH、工具变量、XDG 目录）继承自 zsh；登录 shell 与 `$SHELL` 仍是 zsh，所以 ssh 远程命令、VS Code Remote 等依赖 POSIX 登录 shell 的场景不会受影响。提示符（starship）、外部命令补全（carapace）、zoxide、fzf、mise、direnv 与 wt 的集成都已接好。

## 写法对照

| zsh                             | nu                                  |
| ------------------------------- | ----------------------------------- |
| `a && b`                        | `a; b`（外部命令失败会中止整行）    |
| `a \|\| b`                      | `try { a } catch { b }`             |
| `$(cmd)`                        | `(cmd)`                             |
| `export FOO=x`                  | `$env.FOO = "x"`                    |
| `$FOO`                          | `$env.FOO`                          |
| `FOO=x cmd`                     | 不变                                |
| `$?`                            | `$env.LAST_EXIT_CODE`               |
| `cmd > file`                    | `cmd \| save file` 或 `cmd o> file` |
| `cmd 2>&1 \| ...`               | `cmd o+e>\| ...`                    |
| `cmd > /dev/null`               | `cmd \| ignore`                     |
| `"hi $name"`                    | `$"hi ($name)"`                     |
| `for f in *.txt; do ...; done`  | `for f in (glob *.txt) { ... }`     |
| `-`（oh-my-zsh 别名）           | `cd -`                              |
| zsh 函数（`proxy` / `unproxy`） | 暂未移植，需临时切回 zsh            |
| 网上复制的 bash 一行命令        | `bash -c '...'`                     |

`ls`、`ps`、`rm`、`cp`、`mkdir` 是 nu 内置命令，输出表格、参数与 GNU 版不同，要原版用 `^ls`。
