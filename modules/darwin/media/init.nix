# Settings that only exist behind app APIs (users, logins, server links). Idempotent; run by `media sync`.
{
  cfg,
  pkgs,
  jellyfinUrl,
}:
pkgs.writeShellApplication {
  name = "media-init";
  runtimeInputs = [
    pkgs.curl
    pkgs.jq
  ];
  text = ''
    J=http://127.0.0.1:8096 Q=http://127.0.0.1:8080/api/v2 S=http://127.0.0.1:5055/api/v1 R=http://127.0.0.1:7878/api/v3
    USER=admin
    jar=$(mktemp)
    trap 'rm -f "$jar"' EXIT
    for url in $J/health $Q/app/version $S/status $R/system/status?apikey=$RADARR_API_KEY; do
      until curl -sf -o /dev/null "$url"; do sleep 3; done
    done

    echo "qbittorrent"
    curl -sf $Q/app/setPreferences --data-urlencode "json=$(jq -nc '{
      save_path: "/data/torrents", auto_tmm_enabled: true, max_ratio_act: 0,
      max_ratio_enabled: true, max_ratio: ${toString cfg.seedRatio},
      max_seeding_time_enabled: true, max_seeding_time: ${toString (cfg.seedDays * 1440)}}')"
    curl -s -o /dev/null $Q/torrents/createCategory -d category=movies

    echo "jellyfin"
    auth='MediaBrowser Client="media", Device="init", DeviceId="media-init", Version="1.0"'
    jf() { curl -sf -H "Authorization: $auth" -H 'Content-Type: application/json' "$@"; }
    if [ "$(jf $J/System/Info/Public | jq .StartupWizardCompleted)" != true ]; then
      jf $J/Startup/Configuration -d '{"UICulture":"en-US","MetadataCountryCode":"${cfg.metadataCountry}","PreferredMetadataLanguage":"en"}'
      jf -o /dev/null $J/Startup/User
      jf $J/Startup/User -d "$(jq -nc --arg p "$ADMIN_PASSWORD" '{Name: "admin", Password: $p}')"
      jf -X POST $J/Startup/Complete
    fi
    token=$(jf $J/Users/AuthenticateByName -d "$(jq -nc --arg p "$ADMIN_PASSWORD" '{Username: "admin", Pw: $p}')" | jq -r .AccessToken)
    auth="$auth, Token=\"$token\""
    if ! jf $J/Library/VirtualFolders | jq -e 'any(.Name == "Movies")' >/dev/null; then
      jf "$J/Library/VirtualFolders?name=Movies&collectionType=movies&refreshLibrary=true" \
        -d '{"LibraryOptions":{"EnableRealtimeMonitor":true,"PathInfos":[{"Path":"${cfg.dataDir}/media/movies"}]}}'
    fi
    jf $J/System/Configuration/encoding | jq '. + {
      HardwareAccelerationType: "videotoolbox", HardwareDecodingCodecs: ["h264","hevc","vp9","av1"],
      EnableDecodingColorDepth10Hevc: true, EnableHardwareEncoding: true, AllowHevcEncoding: true,
      EnableTonemapping: true, EnableVideoToolboxTonemapping: true, EnableThrottling: true, EnableSegmentDeletion: true}' \
      | jf $J/System/Configuration/encoding -d @-
    jf $J/System/Configuration | jq '.RemoteClientBitrateLimit = ${
      toString (cfg.remoteBitrateMbps * 1000000)
    }
      | .TrickplayOptions += {EnableHwAcceleration: true, EnableHwEncoding: true}' | jf $J/System/Configuration -d @-
    jf $J/System/Configuration/network | jq '.KnownProxies = ["127.0.0.1"]' | jf $J/System/Configuration/network -d @-

    echo "seerr"
    login=$(jq -nc --arg p "$ADMIN_PASSWORD" '{username: "admin", password: $p}')
    if [ "$(curl -sf $S/settings/public | jq .mediaServerType)" != 2 ]; then
      login=$(jq -c '. + {hostname: "host.docker.internal", port: 8096, useSsl: false, urlBase: "",
        email: "admin@media.local", serverType: 2}' <<<"$login")
    fi
    se() { curl -sf -b "$jar" -c "$jar" -H 'Content-Type: application/json' "$@"; }
    se -o /dev/null $S/auth/jellyfin -d "$login"
    for id in $(se -X POST $S/settings/jellyfin/library/sync | jq -r '.[].id'); do
      se -o /dev/null -X PUT "$S/settings/jellyfin/library/$id" -d '{"enabled":true}'
    done
    se -o /dev/null $S/settings/jellyfin -d '{"externalHostname":"${jellyfinUrl}"}'
    if [ "$(se $S/settings/radarr)" = "[]" ]; then
      profile=$(curl -sf "$R/qualityprofile?apikey=$RADARR_API_KEY" | jq -c 'map(select(.name == "HD-1080p"))[0]')
      jq -nc --argjson p "$profile" --arg key "$RADARR_API_KEY" '{
        name: "Radarr", hostname: "radarr", port: 7878, apiKey: $key, useSsl: false, baseUrl: "",
        activeProfileId: $p.id, activeProfileName: $p.name, activeDirectory: "/data/media/movies",
        minimumAvailability: "released", is4k: false, isDefault: true, syncEnabled: true, preventSearch: false,
        externalUrl: "https://radarr.${cfg.tailnet}", tags: []}' | se -o /dev/null $S/settings/radarr -d @-
    fi
    se -o /dev/null -X POST $S/settings/initialize
    se -o /dev/null $S/settings/main -d '{"applicationUrl":"https://requests.${cfg.tailnet}","cacheImages":true}'
    se -o /dev/null $S/settings/network -d '{"proxy":{"enabled":true,"hostname":"warp","port":1080,
      "bypassFilter":"host.docker.internal, radarr","bypassLocalAddresses":true}}'
    echo "media-init ok"
  '';
}
