{ pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = [
    pkgs.age
    pkgs.sops
    pkgs.tree
  ];

  programs = {
    fish.enable = true;
    starship.enable = true;
    git.enable = true;
    # gh and zellij stay on Homebrew for now (in use); enable to move them to Nix.
    # gh.enable = true;
    # zellij.enable = true;
    btop.enable = true;
  };
}
