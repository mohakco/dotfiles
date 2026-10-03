import base64
import hashlib
import os

from common import E, KEYS, PASSWORD, USER, log

DIRS = ["/data/torrents/movies", "/data/torrents/tv", "/data/media/movies", "/data/media/tv",
        "/config/seerr", "/config/recyclarr", KEYS]


def chown(path):
    try:
        os.chown(path, int(E["PUID"]), int(E["PGID"]))
    except OSError as e:
        log(f"chown {path}: {e}")


def write(path, text):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
        chown(path)


def b64(data):
    return base64.b64encode(data).decode()


def qbit_conf():
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha512", PASSWORD.encode(), salt, 100_000, 64)
    return (
        "[LegalNotice]\nAccepted=true\n\n[Preferences]\n"
        f"WebUI\\Username={USER}\n"
        f'WebUI\\Password_PBKDF2="@ByteArray({b64(salt)}:{b64(digest)})"\n'
        "WebUI\\CSRFProtection=false\n"
    )


def run():
    for path in ["/data", "/data/torrents", "/data/media", *DIRS]:
        os.makedirs(path, exist_ok=True)
        chown(path)
    write("/config/qbittorrent/qBittorrent/qBittorrent.conf", qbit_conf())
    for name in ("jellyfin", "seerr", "bazarr"):
        write(f"{KEYS}/{name}", "")
    log("init ok")
