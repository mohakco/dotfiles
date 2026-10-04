{
  inputs,
  pkgs,
  user,
  ...
}:
{
  imports = [
    inputs.determinate.darwinModules.default
    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.darwinModules.sops
    ../../modules/darwin
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system = {
    primaryUser = user;
    stateVersion = 6;
  };

  networking = {
    hostName = "odysseus";
    computerName = "odysseus";
    localHostName = "odysseus";
  };

  # knownUsers is the only way nix-darwin can set the login shell of an existing user.
  users.knownUsers = [ user ];
  users.users.${user} = {
    uid = 501;
    home = "/Users/${user}";
    shell = pkgs.fish;
  };
  programs.fish.enable = true;

  # Determinate Nixd owns nix.conf and garbage collection (automatic by default).
  determinateNix.enable = true;

  # Headless, so no Touch ID sudo; writing /etc/pam.d also fails over Tailscale SSH (no Full Disk Access).
  security.pam.services.sudo_local.enable = false;

  power = {
    sleep = {
      computer = "never";
      harddisk = "never";
    };
    restartAfterPowerFailure = true;
  };

  # Kept on Homebrew's tailscaled for now: switching drops the SSH session to the Mac.
  # services.tailscale.enable = true;

  # Fallback PATH for brew's tailscale until it moves to Nix.
  environment.systemPath = [ "/opt/homebrew/bin" ];

  homelab = {
    orbstack = {
      enable = true;
      memoryMiB = 6144;
    };
    jellyfin = {
      enable = true;
      mediaDir = "/Volumes/sandisk/data";
      tailscaleServe = true;
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/Users/${user}/.config/sops/age/keys.txt";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    users.${user} = import ../../home;
  };
}
