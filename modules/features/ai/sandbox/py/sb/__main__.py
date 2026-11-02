"""入口：python -m sb <子命令>，由 Nix 打包成 sb。"""

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
