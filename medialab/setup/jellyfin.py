import httpx

from common import E, PASSWORD, USER, client, log, save_key, wait

AUTH = 'MediaBrowser Client="medialab", Device="setup", DeviceId="medialab-setup", Version="1.0"'
LIBRARIES = {"Movies": ("movies", "movies"), "Shows": ("tvshows", "tv")}
ENCODING = {
    "HardwareAccelerationType": E.get("JELLYFIN_HWACCEL", "none"),
    "HardwareDecodingCodecs": ["h264", "hevc", "vp9", "av1"],
    "EnableDecodingColorDepth10Hevc": True,
    "EnableHardwareEncoding": True,
    "AllowHevcEncoding": True,
    "EnableTonemapping": True,
    "EnableVideoToolboxTonemapping": True,
    "EnableThrottling": True,
    "EnableSegmentDeletion": True,
}


def configure(jf, path, **changes):
    jf.post(path, json=jf.get(path).json() | changes)


def wizard(jf):
    if jf.get("/System/Info/Public").json()["StartupWizardCompleted"]:
        return
    jf.post("/Startup/Configuration", json={"UICulture": "en-US", "MetadataCountryCode": E["METADATA_COUNTRY"],
                                             "PreferredMetadataLanguage": "en"})
    jf.get("/Startup/User")
    jf.post("/Startup/User", json={"Name": USER, "Password": PASSWORD})
    jf.post("/Startup/Complete")


def keys(jf):
    return {k["AppName"]: k["AccessToken"] for k in jf.get("/Auth/Keys").json()["Items"]}


def api_key(jf):
    if "medialab" not in keys(jf):
        jf.post("/Auth/Keys", params={"app": "medialab"})
    return keys(jf)["medialab"]


def wire():
    wait(f"{E['JELLYFIN_URL']}/health")
    jf = client(E["JELLYFIN_URL"], headers={"Authorization": AUTH})
    wizard(jf)
    token = jf.post("/Users/AuthenticateByName", json={"Username": USER, "Pw": PASSWORD}).json()["AccessToken"]
    jf.headers["Authorization"] = f'{AUTH}, Token="{token}"'
    existing = {f["Name"] for f in jf.get("/Library/VirtualFolders").json()}
    for name, (kind, folder) in LIBRARIES.items():
        if name not in existing:
            try:
                jf.post("/Library/VirtualFolders", params={"name": name, "collectionType": kind, "refreshLibrary": True},
                        json={"LibraryOptions": {"PathInfos": [{"Path": f"{E['DATA_DIR']}/media/{folder}"}]}})
            except httpx.ReadTimeout:
                raise SystemExit("Jellyfin cannot read the media drive yet: click Allow on the macOS prompt for "
                                 "'Jellyfin Server' (removable volume), then run make up again")
    configure(jf, "/System/Configuration/encoding", **ENCODING)
    system = jf.get("/System/Configuration").json()
    system["RemoteClientBitrateLimit"] = int(E["REMOTE_BITRATE_MBPS"]) * 1_000_000
    system["TrickplayOptions"] |= {"EnableHwAcceleration": True, "EnableHwEncoding": True}
    jf.post("/System/Configuration", json=system)
    configure(jf, "/System/Configuration/network", KnownProxies=["127.0.0.1"])
    key = api_key(jf)
    save_key("jellyfin", key)
    log("jellyfin ok")
    return key
