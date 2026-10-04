{ pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = [
    pkgs.age
    pkgs.sops
  ];

  programs = {
    fish.enable = true;
    git.enable = true;
    gh.enable = true;
    zellij.enable = true;
    btop.enable = true;
  };
}
