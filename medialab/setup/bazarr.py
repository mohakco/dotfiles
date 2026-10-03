import json

import yaml

from common import E, PASSWORD, USER, client, csv, log, save_key, wait

URL = "http://bazarr:6767"
CONFIG = "/config/bazarr/config/config.yaml"


def profile(languages):
    items = [{"id": i, "language": code, "hi": "False", "forced": "False", "audio_exclude": "False"}
             for i, code in enumerate(languages, 1)]
    return {"profileId": 1, "name": "Default", "cutoff": None, "items": items,
            "mustContain": [], "mustNotContain": [], "originalFormat": False, "tag": None}


def wire():
    wait(URL)
    with open(CONFIG) as f:
        key = yaml.safe_load(f)["auth"]["apikey"]
    languages = csv("SUBTITLE_LANGS")
    client(f"{URL}/api", headers={"X-API-KEY": key}).post("/system/settings", data={
        "languages-enabled": languages,
        "languages-profiles": json.dumps([profile(languages)]),
        "settings-general-enabled_providers": csv("SUBTITLE_PROVIDERS"),
        "settings-general-use_sonarr": "true",
        "settings-general-use_radarr": "true",
        "settings-general-serie_default_enabled": "true",
        "settings-general-serie_default_profile": "1",
        "settings-general-movie_default_enabled": "true",
        "settings-general-movie_default_profile": "1",
        "settings-sonarr-ip": "sonarr",
        "settings-sonarr-apikey": E["SONARR_API_KEY"],
        "settings-radarr-ip": "radarr",
        "settings-radarr-apikey": E["RADARR_API_KEY"],
        "settings-auth-type": "form",
        "settings-auth-username": USER,
        "settings-auth-password": PASSWORD,
    })
    save_key("bazarr", key)
    log("bazarr ok")
