{ cfg, lib }:
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

  # A web app published on 127.0.0.1 and on https://<tsName>.<tailnet> via TSDProxy.
  app =
    name: port: tsName: extra:
    lib.recursiveUpdate {
      container_name = name;
      restart = "unless-stopped";
      environment = ids;
      ports = [ "127.0.0.1:${toString port}:${toString port}" ];
      labels = {
        "tsdproxy.enable" = "true";
        "tsdproxy.name" = tsName;
        "tsdproxy.port.1" = "443/https:${toString port}/http";
      };
    } extra;

  arr = name: port: key: image: {
    inherit image;
    environment = {
      "${lib.toUpper name}__AUTH__APIKEY" = "\${${key}}";
      # Tailnet-only access is the auth until authentik fronts these (P5).
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

    tsdproxy = app "tsdproxy" 8088 "tsdproxy" {
      image = "almeidapaulopt/tsdproxy:2.3.4";
      ports = [ "127.0.0.1:8088:8080" ];
      labels."tsdproxy.port.1" = "443/https:8080/http";
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
      ];
    };

    qbittorrent = app "qbittorrent" 8080 "qbit" {
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

    radarr = app "radarr" 7878 "radarr" (
      arr "radarr" 7878 "RADARR_API_KEY" "lscr.io/linuxserver/radarr:6.4.4.10685-ls318"
      // {
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        volumes = [
          "${state "radarr"}:/config"
          data
        ];
      }
    );

    prowlarr = app "prowlarr" 9696 "prowlarr" (
      arr "prowlarr" 9696 "PROWLARR_API_KEY" "lscr.io/linuxserver/prowlarr:2.6.5.5623-ls162"
      // {
        volumes = [ "${state "prowlarr"}:/config" ];
      }
    );

    seerr = app "seerr" 5055 "requests" {
      image = "ghcr.io/seerr-team/seerr:v3.5.0";
      init = true;
      user = "${ids.PUID}:${ids.PGID}";
      environment.PORT = 5055;
      extra_hosts = [ "host.docker.internal:host-gateway" ];
      volumes = [ "${state "seerr"}:/app/config" ];
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
      http.port = 8080;
      log.level = "info";
      proxyAccessLog = false;
    };
  };

  secrets.ts_authkey.environment = "TS_AUTHKEY";
}
