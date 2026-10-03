import qbittorrentapi

from common import E, PASSWORD, USER, log, wait

URL = "http://qbittorrent:8080"


def wire():
    wait(URL)
    qb = qbittorrentapi.Client(host=URL, username=USER, password=PASSWORD)
    qb.app_set_preferences({
        "save_path": "/data/torrents",
        "auto_tmm_enabled": True,
        "max_ratio_enabled": True,
        "max_ratio": float(E["SEED_RATIO"]),
        "max_seeding_time_enabled": True,
        "max_seeding_time": int(E["SEED_DAYS"]) * 1440,
        "max_ratio_act": 0,
    })
    for category in {"movies", "tv"} - set(qb.torrents_categories()):
        qb.torrents_create_category(category)
    log("qbittorrent ok")
