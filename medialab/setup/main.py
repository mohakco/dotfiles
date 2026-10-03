# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "backoff==2.2.1",
#   "httpx==0.28.1",
#   "pyarr==6.9.0",
#   "pyyaml==6.0.3",
#   "qbittorrent-api==2026.10.0",
# ]
# ///
import sys

import arr
import bazarr
import init
import jellyfin
import qbit
import seerr


def wire():
    qbit.wire()
    arr.wire()
    bazarr.wire()
    arr.notify_jellyfin(jellyfin.wire())
    seerr.wire()


if __name__ == "__main__":
    init.run() if sys.argv[1:] == ["init"] else wire()
