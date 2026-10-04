# maclab

Nix flake for my machines. Today: `odysseus`, a Mac mini M4 running a media server.

## odysseus

| URL (tailnet only) | What |
|---|---|
| `https://odysseus.impala-codlet.ts.net` | Jellyfin (own login; Infuse uses `admin` + the shared password) |
| `https://requests.impala-codlet.ts.net` | Seerr |
| `https://radarr.…`, `prowlarr.…`, `qbit.…` | Radarr, Prowlarr, qBittorrent |
| `https://auth.impala-codlet.ts.net` | Authelia: passkey (or password) login in front of everything except Jellyfin |

```bash
nix run .#odysseus                 # apply (asks for sudo)
nix run .#odysseus -- --rollback   # previous generation
media ps | media logs -f radarr    # docker compose for the stack, secrets loaded
media sync                         # converge: compose up, Configarr, media-init
sops secrets/secrets.yaml          # edit secrets
```

### Fresh Mac

1. Install Determinate Nix and restore the age key to `~/.config/sops/age/keys.txt`.
2. Plug in the media drive (`/Volumes/sandisk`), clone this repo, run `nix run .#odysseus`.
3. Click Allow on the macOS prompt for Jellyfin's removable-volume access; turn on automatic login.
4. Sign in at `auth.…` with the password, then add a passkey under Settings → Two-Factor Authentication (the one-time code is in `~/.local/share/media/authelia/notification.txt`).
