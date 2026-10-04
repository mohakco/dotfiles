{ pkgs, ... }:
{
  home.stateVersion = "26.05";

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
