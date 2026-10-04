{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.orbstack;
in
{
  options.homelab.orbstack = {
    enable = lib.mkEnableOption "OrbStack container runtime";
    memoryMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "Memory limit of the OrbStack Linux VM.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "orbstack";
    environment.systemPackages = [ pkgs.orbstack ];

    launchd.user.agents.orbstack = {
      command = "${lib.getExe pkgs.orbstack} start";
      serviceConfig.RunAtLoad = true;
    };

    # Applies once OrbStack has started; harmless no-op before that.
    system.activationScripts.postActivation.text = ''
      sudo -u ${config.system.primaryUser} ${lib.getExe pkgs.orbstack} config set memory_mib ${toString cfg.memoryMiB} || true
    '';
  };
}
