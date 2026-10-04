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
    orbstack.memoryMiB = 6144;
    media = {
      enable = true;
      dataDir = "/Volumes/sandisk/data";
      tailnet = "impala-codlet.ts.net";
      auth = {
        inherit user;
        email = "mohakmalhotra0209@gmail.com";
      };
      timeZone = "Asia/Kolkata";
      metadataCountry = "IN";
      indexers = [
        "1337x"
        "thepiratebay"
        "yts"
        "limetorrents"
        "knaben"
        "nyaasi"
      ];
      cloudflareIndexers = [ "1337x" ];
      quality = {
        minMbPerMin = 10;
        preferredMbPerMin = 20;
        maxMbPerMin = 35;
      };
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
