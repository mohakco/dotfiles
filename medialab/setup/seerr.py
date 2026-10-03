from urllib.parse import urlsplit

import arr
from common import E, PASSWORD, USER, client, log, save_key, wait

URL = "http://seerr:5055/api/v1"
JELLYFIN = 2


def server(kind):
    api = arr.connect(kind)
    profile = next(p for p in api.quality_profile.get() if p["name"] == "HD-1080p")
    root = arr.APPS[kind][2]
    body = {"name": kind.title(), "hostname": kind, "port": arr.APPS[kind][1], "apiKey": E[f"{kind.upper()}_API_KEY"],
            "useSsl": False, "baseUrl": "", "activeProfileId": profile["id"], "activeProfileName": profile["name"],
            "activeDirectory": root, "is4k": False, "isDefault": True, "syncEnabled": True, "preventSearch": False,
            "externalUrl": f"https://{kind}.{E['TAILNET']}", "tags": []}
    if kind == "radarr":
        return body | {"minimumAvailability": "released"}
    return body | {"activeAnimeProfileId": profile["id"], "activeAnimeProfileName": profile["name"],
                   "activeAnimeDirectory": root, "seriesType": "standard", "animeSeriesType": "anime",
                   "enableSeasonFolders": True, "animeTags": []}


def wire():
    wait(f"{URL}/status")
    seerr = client(URL)
    login = {"username": USER, "password": PASSWORD}
    if seerr.get("/settings/public").json()["mediaServerType"] != JELLYFIN:
        jellyfin = urlsplit(E["JELLYFIN_URL"])
        login |= {"hostname": jellyfin.hostname, "port": jellyfin.port, "useSsl": False, "urlBase": "",
                  "email": f"{USER}@medialab.local", "serverType": JELLYFIN}
    seerr.post("/auth/jellyfin", json=login)
    for library in seerr.post("/settings/jellyfin/library/sync").json():
        seerr.put(f"/settings/jellyfin/library/{library['id']}", json={"enabled": True})
    seerr.post("/settings/jellyfin", json={"externalHostname": E["JELLYFIN_PUBLIC_URL"]})
    for kind in ("radarr", "sonarr"):
        if not seerr.get(f"/settings/{kind}").json():
            seerr.post(f"/settings/{kind}", json=server(kind))
    seerr.post("/settings/initialize")
    seerr.post("/settings/main", json={"applicationUrl": f"https://requests.{E['TAILNET']}", "cacheImages": True})
    seerr.post("/settings/network", json={"proxy": {"enabled": True, "hostname": "warp", "port": 1080,
                                                    "bypassFilter": "host.docker.internal, radarr, sonarr",
                                                    "bypassLocalAddresses": True}})
    save_key("seerr", seerr.get("/settings/main").json()["apiKey"])
    log("seerr ok")
