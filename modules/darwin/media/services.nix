{
  cfg,
  lib,
  auth,
}:
let
  ids = {
    PUID = toString cfg.uid;
    PGID = "20";
    TZ = cfg.timeZone;
  };
  state = name: "${cfg.stateDir}/${name}";
  # A missing drive must fail loudly instead of filling the internal SSD.
  data = {
    type = "bind";
    source = cfg.dataDir;
    target = "/data";
    bind.create_host_path = false;
  };

  # A web app on 127.0.0.1 only; the tailnet reaches it through Caddy + Authelia.
  app =
    name: port: extra:
    lib.recursiveUpdate {
      container_name = name;
      restart = "unless-stopped";
      environment = ids;
      ports = [ "127.0.0.1:${toString port}:${toString port}" ];
    } extra;

  url = name: "https://${name}.${cfg.tailnet}";
  tile = name: href: icon: description: extra: {
    ${name} = {
      inherit href icon description;
    }
    // extra;
  };
  homepage = {
    settings = {
      title = "odysseus";
      theme = "dark";
      headerStyle = "clean";
    };
    widgets = [ ];
    services = [
      {
        Watch = [
          (tile "Jellyfin" (url "odysseus") "jellyfin.png" "Movies" { })
          (tile "Seerr" (url "requests") "jellyseerr.png" "Request a movie" { })
        ];
      }
      {
        Downloads = [
          (tile "Radarr" (url "radarr") "radarr.png" "Movies" {
            widget = {
              type = "radarr";
              url = "http://radarr:7878";
              key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
            };
          })
          (tile "Prowlarr" (url "prowlarr") "prowlarr.png" "Indexers" {
            widget = {
              type = "prowlarr";
              url = "http://prowlarr:9696";
              key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
            };
          })
          (tile "Bazarr" (url "subs") "bazarr.png" "Subtitles" { })
          (tile "qBittorrent" (url "qbit") "qbittorrent.png" "Torrents" {
            widget = {
              type = "qbittorrent";
              url = "http://qbittorrent:8080";
            };
          })
        ];
      }
      {
        System = [ (tile "Authelia" (url "auth") "authelia.png" "Login and passkeys" { }) ];
      }
    ];
  };

  arr = name: port: key: image: {
    inherit image;
    environment = {
      "${lib.toUpper name}__AUTH__APIKEY" = "\${${key}}";
      # Authelia in front of Caddy is the login.
      "${lib.toUpper name}__AUTH__METHOD" = "External";
    };
  };
in
{
  services = {
    warp = {
      image = "caomingjun/warp:2026.7.1377.0-2.12.0";
      container_name = "warp";
      restart = "unless-stopped";
      device_cgroup_rules = [ "c 10:200 rwm" ];
      cap_add = [
        "MKNOD"
        "AUDIT_WRITE"
        "NET_ADMIN"
      ];
      sysctls = {
        "net.ipv6.conf.all.disable_ipv6" = 0;
        "net.ipv4.conf.all.src_valid_mark" = 1;
      };
      environment.WARP_SLEEP = 2;
      ports = [ "127.0.0.1:1080:1080" ];
      volumes = [ "${state "warp"}:/var/lib/cloudflare-warp" ];
      # WARP hangs on OrbStack; autoheal restarts it when its healthcheck fails.
      labels.autoheal = "true";
    };

    autoheal = {
      image = "willfarrell/autoheal:1.2.0";
      container_name = "autoheal";
      restart = "unless-stopped";
      volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2";
      container_name = "flaresolverr";
      restart = "unless-stopped";
      depends_on.warp.condition = "service_healthy";
      # network_mode: service:warp breaks FlareSolverr on OrbStack, so it uses the proxy instead.
      environment = {
        inherit (ids) TZ;
        HTTP_PROXY = "http://warp:1080";
        HTTPS_PROXY = "http://warp:1080";
        NO_PROXY = "localhost,127.0.0.1";
      };
      healthcheck = {
        test = [
          "CMD"
          "curl"
          "-sf"
          "http://localhost:8191/health"
        ];
        interval = "30s";
        start_period = "30s";
      };
    };

    # One tailnet machine per gated app, all pointing at Caddy, which routes by Host.
    tsdproxy = {
      image = "almeidapaulopt/tsdproxy:2.3.4";
      container_name = "tsdproxy";
      restart = "unless-stopped";
      secrets = [ "ts_authkey" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "${state "tsdproxy"}:/data"
      ];
      configs = [
        {
          source = "tsdproxy";
          target = "/config/tsdproxy.yaml";
        }
        {
          source = "tsdproxy-apps";
          target = "/config/apps.yaml";
        }
      ];
    };

    qbittorrent = app "qbittorrent" 8080 {
      image = "lscr.io/linuxserver/qbittorrent:5.2.4_v2.0.15-ls479";
      environment = {
        WEBUI_PORT = 8080;
        TORRENTING_PORT = 6881;
      };
      ports = [
        "127.0.0.1:8080:8080"
        "6881:6881"
        "6881:6881/udp"
      ];
      volumes = [
        "${state "qbittorrent"}:/config"
        data
      ];
    };

    radarr = app "radarr" 7878 (
      arr "radarr" 7878 "RADARR_API_KEY" "lscr.io/linuxserver/radarr:6.4.4.10685-ls318"
      // {
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        volumes = [
          "${state "radarr"}:/config"
          data
        ];
      }
    );

    prowlarr = app "prowlarr" 9696 (
      arr "prowlarr" 9696 "PROWLARR_API_KEY" "lscr.io/linuxserver/prowlarr:2.6.5.5623-ls162"
      // {
        volumes = [ "${state "prowlarr"}:/config" ];
      }
    );

    bazarr = app "bazarr" 6767 {
      image = "lscr.io/linuxserver/bazarr:v1.6.2-ls366";
      volumes = [
        "${state "bazarr"}:/config"
        data
      ];
    };

    seerr = app "seerr" 5055 {
      image = "ghcr.io/seerr-team/seerr:v3.5.0";
      init = true;
      user = "${ids.PUID}:${ids.PGID}";
      environment.PORT = 5055;
      extra_hosts = [ "host.docker.internal:host-gateway" ];
      volumes = [ "${state "seerr"}:/app/config" ];
    };

    # Dashboard; every tile and widget comes from the Nix-generated YAML below.
    homepage = {
      image = "ghcr.io/gethomepage/homepage:v2.4.0";
      container_name = "homepage";
      restart = "unless-stopped";
      environment = {
        HOMEPAGE_ALLOWED_HOSTS = "home.${cfg.tailnet}";
        HOMEPAGE_VAR_RADARR_KEY = "\${RADARR_API_KEY}";
        HOMEPAGE_VAR_PROWLARR_KEY = "\${PROWLARR_API_KEY}";
      };
      configs = map (name: {
        source = "homepage-${name}";
        target = "/app/config/${name}.yaml";
      }) (lib.attrNames homepage);
    };

    # One-shot, run by `media sync` after the apps are up.
    configarr = {
      image = "ghcr.io/raydak-labs/configarr:1.34.0";
      container_name = "configarr";
      profiles = [ "jobs" ];
      environment.SECRETS_LOCATION = "/app/config/*.secrets.yml";
      volumes = [ "${state "configarr"}:/app/repos" ];
      configs = [
        {
          source = "configarr";
          target = "/app/config/config.yml";
        }
      ];
    };
  };

  # JSON is valid YAML; compose fills in ${VAR} from the sops env file.
  configs = {
    configarr.content = builtins.toJSON (import ./configarr.nix { inherit cfg; });
    tsdproxy.content = builtins.toJSON {
      defaultProxyProvider = "default";
      docker.local = {
        host = "unix:///var/run/docker.sock";
        targetHostname = "host.docker.internal";
        tryDockerInternalNetwork = true;
        defaultProxyProvider = "default";
      };
      tailscale = {
        providers.default.authKeyFile = "/run/secrets/ts_authkey";
        dataDir = "/data/";
      };
      lists.apps = {
        filename = "/config/apps.yaml";
        defaultProxyProvider = "default";
      };
      http.port = 8080;
      log.level = "info";
      proxyAccessLog = false;
    };
    "tsdproxy-apps".content = builtins.toJSON (
      lib.genAttrs ([ "auth" ] ++ lib.attrNames (auth.apps // auth.openApps)) (_: {
        ports."443/https".targets = [ "http://caddy:8099" ];
      })
    );
  }
  // lib.mapAttrs' (
    name: value: lib.nameValuePair "homepage-${name}" { content = builtins.toJSON value; }
  ) homepage;

  secrets.ts_authkey.environment = "TS_AUTHKEY";
}
