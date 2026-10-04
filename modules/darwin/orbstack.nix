{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.orbstack;
  orb = lib.getExe pkgs.orbstack;
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
      script = ''
        ${orb} config set memory_mib ${toString cfg.memoryMiB}
        ${orb} start
      '';
      serviceConfig.RunAtLoad = true;
    };
  };
}
