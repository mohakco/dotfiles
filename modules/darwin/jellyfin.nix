{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.jellyfin;
  home = config.users.users.${config.system.primaryUser}.home;
in
{
  options.homelab.jellyfin = {
    enable = lib.mkEnableOption "native Jellyfin (VideoToolbox transcoding)";
    package = lib.mkPackageOption pkgs "jellyfin" { };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Library/Application Support/jellyfin";
    };
    mediaDir = lib.mkOption {
      type = lib.types.str;
      description = "Jellyfin only runs while this path exists, so a missing drive stops it.";
    };
    proxy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://127.0.0.1:1080";
      description = "HTTP proxy for metadata lookups.";
    };
    tailscaleServe = lib.mkEnableOption "publishing Jellyfin on https://<host>.<tailnet> with tailscale serve";
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.jellyfin.serviceConfig = {
      ProgramArguments = [
        (lib.getExe cfg.package)
        "--datadir"
        cfg.dataDir
        "--cachedir"
        "${home}/Library/Caches/jellyfin"
      ];
      KeepAlive.PathState.${cfg.mediaDir} = true;
      # Background agents get throttled CPU/GPU; transcoding needs full priority.
      ProcessType = "Interactive";
      EnvironmentVariables = lib.mkIf (cfg.proxy != null) {
        HTTP_PROXY = cfg.proxy;
        HTTPS_PROXY = cfg.proxy;
        NO_PROXY = "localhost,127.0.0.1,host.docker.internal";
      };
      StandardOutPath = "${home}/Library/Logs/jellyfin.log";
      StandardErrorPath = "${home}/Library/Logs/jellyfin.log";
    };

    system.activationScripts.postActivation.text = lib.mkIf cfg.tailscaleServe ''
      ${lib.getExe pkgs.tailscale} serve --bg --https=443 http://127.0.0.1:8096 >/dev/null || true
    '';
  };
}
