# dotfiles

Personal Nix flake for every machine (nix-darwin + home-manager + sops-nix). Single user, no sharing concerns. Hosts live in `hosts/<name>/`, reusable modules in `modules/darwin/` under the `homelab.*` namespace, shared home config in `home/`.

## Rules

- Reuse before writing: a nixpkgs package, an upstream module option or a maintained tool (Configarr, TSDProxy lists, Authelia) beats custom code. Search the web for current best practice before adding anything.
- Keep code short and flat; comment only a non-obvious gotcha.
- Tunables are module options set in `hosts/<name>/default.nix`; secrets live only in the sops-encrypted `secrets/secrets.yaml` (edit with `sops`, render with `sops.templates`).
- Pin exact image tags; `flake.lock` pins everything else. Bumping either is a deliberate commit.
- Applying is idempotent: `nix run .#odysseus` switches the Mac, and the `media` launchd agent re-runs `media sync` (compose up, Configarr, `media-init`) whenever the compose file changes.
- Media drive mounts use `create_host_path: false` so a missing drive fails loudly instead of filling the internal SSD.
- Verify by evaluating on the laptop (`nix eval .#darwinConfigurations.odysseus.system.drvPath`), building on the Mac, then exercising the changed path on the running stack.

## Gotchas

- The laptop is x86_64 Linux: it evaluates `aarch64-darwin` but cannot build it. Build and switch on the Mac (`ssh mohak@odysseus`; wrap commands in `zsh -l -s`, the login shell is fish).
- Containers run on OrbStack; nixpkgs lacks darwin builds of Authelia's web UI, Seerr and FlareSolverr, so those stay containers. Jellyfin runs natively for VideoToolbox.
- Compose inline `configs` changes do not recreate a container on their own; the `nix.config-hash` label does.
- macOS asks once per Jellyfin binary for removable-volume access; after a Jellyfin bump, click Allow on the Mac (via RustDesk).
- Authelia has no mail server: one-time codes land in `~/.local/share/media/authelia/notification.txt` on the Mac.
