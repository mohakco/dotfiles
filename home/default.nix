{ config, pkgs, ... }:
{
  home.stateVersion = "26.05";

  # sops on macOS otherwise looks under ~/Library/Application Support.
  home.sessionVariables.SOPS_AGE_KEY_FILE = "${config.xdg.configHome}/sops/age/keys.txt";

  home.packages = [
    pkgs.age
    pkgs.sops
    pkgs.tree
  ];

  xdg.configFile."zellij/config.kdl".source = ./zellij/config.kdl;

  programs = {
    fish.enable = true;
    starship.enable = true;
    git.enable = true;
    gh = {
      enable = true;
      settings.aliases.co = "pr checkout";
    };
    zellij = {
      enable = true;
      # Integration would auto-start zellij in every fish shell.
      enableFishIntegration = false;
    };
    btop.enable = true;
  };
}
