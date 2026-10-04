{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.media;
  home = config.users.users.${config.system.primaryUser}.home;
  auth = import ./auth.nix {
    inherit cfg;
    inherit (config.networking) hostName;
  };
  secrets = [
    "ADMIN_PASSWORD"
    "RADARR_API_KEY"
    "PROWLARR_API_KEY"
    "TS_AUTHKEY"
  ]
  ++ auth.envSecrets;

  compose = (pkgs.formats.yaml { }).generate "compose.yaml" (
    lib.recursiveUpdate (import ./services.nix { inherit cfg lib auth; }) {
      inherit (auth) services configs;
    }
  );
  init = import ./init.nix {
    inherit cfg pkgs;
    jellyfinUrl = "https://${config.networking.hostName}.${cfg.tailnet}";
  };

  media = pkgs.writeShellApplication {
    name = "media";
    runtimeInputs = [
      pkgs.orbstack
      pkgs.curl
      init
    ];
    text = ''
      export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
      set -a
      # shellcheck disable=SC1091
      . ${config.sops.templates."media.env".path}
      set +a
      dc() { docker compose -p media -f ${compose} "$@"; }

      if [ "''${1:-}" != sync ]; then
        dc "$@"
        exit
      fi
      mkdir -p "${cfg.dataDir}/torrents/movies" "${cfg.dataDir}/media/movies" "${cfg.stateDir}/qbittorrent/qBittorrent"
      # Seeded once: qBittorrent rewrites this file, the rest of its settings come from media-init.
      cp -n ${./qBittorrent.conf} "${cfg.stateDir}/qbittorrent/qBittorrent/qBittorrent.conf" || true
      dc up -d --wait --remove-orphans
      # A cold FlareSolverr can time out Prowlarr's indexer test on the first run; it passes once warm.
      dc run --rm configarr || dc run --rm configarr
      media-init
      curl -sf localhost:5055/api/v1/status | grep -q '"restartRequired":true' && dc restart seerr || true
    '';
  };
in
{
  options.homelab.media = {
    enable = lib.mkEnableOption "the media stack (Radarr, Prowlarr, qBittorrent, Seerr on OrbStack)";
    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Torrents and media in one tree, so imports are hardlinks.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/media";
    };
    tailnet = lib.mkOption { type = lib.types.str; };
    auth = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "The only Authelia user; signs in with a passkey.";
      };
      email = lib.mkOption { type = lib.types.str; };
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = config.users.users.${config.system.primaryUser}.uid;
    };
    indexers = lib.mkOption { type = lib.types.listOf lib.types.str; };
    cloudflareIndexers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Indexers that need FlareSolverr.";
    };
    quality = {
      minMbPerMin = lib.mkOption { type = lib.types.number; };
      preferredMbPerMin = lib.mkOption { type = lib.types.number; };
      maxMbPerMin = lib.mkOption { type = lib.types.number; };
    };
    seedRatio = lib.mkOption {
      type = lib.types.number;
      default = 1;
    };
    seedDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
    };
    minFreeMb = lib.mkOption {
      type = lib.types.int;
      default = 5000;
    };
    metadataCountry = lib.mkOption {
      type = lib.types.str;
      default = "US";
    };
    remoteBitrateMbps = lib.mkOption {
      type = lib.types.int;
      default = 35;
    };
  };

  config = lib.mkIf cfg.enable {
    homelab.orbstack.enable = true;
    homelab.jellyfin = {
      enable = true;
      mediaDir = cfg.dataDir;
      proxy = "http://127.0.0.1:1080";
      tailscaleServe = true;
    };

    environment.systemPackages = [ media ];

    sops.secrets = lib.genAttrs secrets (_: { });
    sops.templates."media.env" = {
      owner = config.system.primaryUser;
      # Single quotes: the Authelia password hash contains `$`, which the shell would expand.
      content = lib.concatMapStrings (k: "${k}='${config.sops.placeholder.${k}}'\n") secrets;
    };

    # A new compose file changes this agent, so every switch that touches the stack re-syncs it.
    launchd.user.agents.media = {
      script = ''
        /bin/wait4path ${cfg.dataDir}
        until ${pkgs.orbstack}/bin/docker info >/dev/null 2>&1; do sleep 5; done
        ${lib.getExe media} sync
      '';
      serviceConfig = {
        RunAtLoad = true;
        StandardOutPath = "${home}/Library/Logs/media.log";
        StandardErrorPath = "${home}/Library/Logs/media.log";
      };
    };
  };
}
