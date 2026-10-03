from urllib.parse import urlsplit

from pyarr import Prowlarr, Radarr, Sonarr
from pyarr.exceptions import PyarrBadRequest

from common import E, PASSWORD, USER, csv, fields, log, wait

APPS = {
    "sonarr": (Sonarr, 8989, "/data/media/tv", {"tvCategory": "tv"}),
    "radarr": (Radarr, 7878, "/data/media/movies", {"movieCategory": "movies"}),
    "prowlarr": (Prowlarr, 9696, None, None),
}
EVENTS = ("Download", "Upgrade", "Rename", "Delete", "ImportComplete")


def url(name):
    return f"http://{name}:{APPS[name][1]}"


def connect(name):
    wait(f"{url(name)}/ping")
    return APPS[name][0](url(name), E[f"{name.upper()}_API_KEY"])


def login(api):
    host = api.http_utils.request("config/host")
    if host.get("username") != USER:
        host |= {"authenticationMethod": "forms", "authenticationRequired": "enabled",
                 "username": USER, "password": PASSWORD, "passwordConfirmation": PASSWORD}
        api.http_utils.request(f"config/host/{host['id']}", method="PUT", json_data=host)


def media(name):
    api = connect(name)
    _, _, root, category = APPS[name]
    login(api)
    if root not in {r["path"].rstrip("/") for r in api.root_folder.get()}:
        api.root_folder.add(root)
    if not api.download_client.get():
        schema = api.download_client.get_schema("QBittorrent")[0]
        fields(schema, host="qbittorrent", port=8080, username=USER, password=PASSWORD, **category)
        api.download_client.add(schema | {"name": "qBittorrent", "enable": True})
    mm = api.http_utils.request("config/mediamanagement")
    mm["minimumFreeSpaceWhenImporting"] = int(E["MIN_FREE_MB"])
    api.http_utils.request(f"config/mediamanagement/{mm['id']}", method="PUT", json_data=mm)
    log(f"{name} ok")


def prowlarr():
    api = connect("prowlarr")
    request = api.http_utils.request
    login(api)
    tags = {t["label"]: t["id"] for t in api.tag.get()}
    for label in {"warp", "flaresolverr"} - tags.keys():
        tags[label] = api.tag.create(label)["id"]
    proxies = {p["name"] for p in api.indexer_proxy.get()}
    for name, values in {"FlareSolverr": {"host": "http://warp:8191/", "requestTimeout": 60},
                         "Socks5": {"host": "warp", "port": 1080}}.items():
        if name not in proxies:
            schema = next(s for s in request("indexerProxy/schema") if s["implementation"] == name)
            tag = tags["flaresolverr" if name == "FlareSolverr" else "warp"]
            api.indexer_proxy.add(fields(schema, **values) | {"name": name, "tags": [tag]})
    apps = {a["name"] for a in api.applications.get()}
    for name in ("Sonarr", "Radarr"):
        if name not in apps:
            schema = next(s for s in request("applications/schema") if s["implementation"] == name)
            fields(schema, prowlarrUrl=url("prowlarr"), baseUrl=url(name.lower()), apiKey=E[f"{name.upper()}_API_KEY"])
            api.applications.add(schema | {"name": name, "syncLevel": "fullSync"})
    have = {i["definitionName"].lower() for i in api.indexer.get()}
    schemas = {s["definitionName"].lower(): s for s in api.indexer.get_schema()}
    cloudflare = {n.lower() for n in csv("CLOUDFLARE_INDEXERS")}
    for name in [n.lower() for n in csv("INDEXERS") if n.lower() not in have]:
        indexer_tags = [tags["warp"]] + ([tags["flaresolverr"]] if name in cloudflare else [])
        try:
            request("indexer", method="POST", json_data=schemas[name] | {"enable": True, "appProfileId": 1, "tags": indexer_tags})
            have.add(name)
        except (KeyError, PyarrBadRequest) as e:
            log(f"prowlarr: skipped {name}: {str(e)[:200]}")
    api.command.execute("ApplicationIndexerSync")
    log("prowlarr ok:", ", ".join(sorted(have)))


def wire():
    media("sonarr")
    media("radarr")
    prowlarr()


def notify_jellyfin(key):
    jellyfin = urlsplit(E["JELLYFIN_URL"])
    for name in ("sonarr", "radarr"):
        api = connect(name)
        if any(n["implementation"] == "MediaBrowser" for n in api.notification.get()):
            continue
        schema = api.notification.get_schema("MediaBrowser")[0]
        fields(schema, host=jellyfin.hostname, port=jellyfin.port, apiKey=key, updateLibrary=True,
               mapFrom="/data/media/", mapTo=f"{E['DATA_DIR']}/media/")
        events = {k: True for k in schema if k.startswith("on") and k.endswith(EVENTS)}
        api.notification.add(schema | events | {"name": "Jellyfin"})
    log("jellyfin notifications ok")
