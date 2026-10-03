# medialab

Request a title in Seerr, Radarr/Sonarr grab it through Prowlarr, qBittorrent downloads it to the media drive, Bazarr adds subtitles, Jellyfin streams it. Jellyfin runs natively on macOS for VideoToolbox; everything else runs in OrbStack. Every UI gets its own `https://<name>.<tailnet>.ts.net` address.

## Layout

```
.env                 every tunable: paths, tailnet, size caps, seeding, indexers, subtitles
secrets.env          sops+age encrypted: admin password, API keys, Tailscale auth key
Makefile             the only entrypoint
compose.yaml         includes the app groups below
network/             warp (Cloudflare WARP proxy for ISP-blocked sites), flaresolverr, tsdproxy, autoheal (restarts warp when unhealthy)
downloads/           qbittorrent
arr/                 sonarr, radarr, prowlarr, bazarr, recyclarr (quality sizes, x265 preference)
requests/            seerr
dashboard/           homepage
setup/               init (pre-start files) and setup (API wiring), Python run by uv
macos/               Jellyfin LaunchAgent
config/              app state, gitignored
```

## Install, or restore after a format

1. Install tools: `brew install sops age` and `brew install --cask orbstack jellyfin`. Tailscale stays on `brew services`.
2. Tailscale admin console: enable MagicDNS and HTTPS certificates.
3. Edit `.env`: `TAILNET`, `MEDIA_VOLUME`, `PUID` (`id -u`), `PGID` (`id -g`).
4. First install: create a reusable auth key in the Tailscale admin console, then run `TS_AUTHKEY=tskey-auth-... make`. It creates the age key in `~/.config/sops/age/keys.txt` and an encrypted `secrets.env`. Save the age key in your password manager and commit `secrets.env`.
5. After a format: restore `~/.config/sops/age/keys.txt`, clone the repo, run `make`.
6. Once, by hand: automatic login (System Settings, Users & Groups) and OrbStack "Start at login". Leave "Launch at Login" off in Jellyfin's menu bar icon; the LaunchAgent starts it.
7. First `make` only: macOS asks whether "Jellyfin Server" may access files on a removable volume. Click **Allow** on the Mac's screen (missed it: System Settings, Privacy & Security, Files & Folders, Jellyfin Server, Removable Volumes), then `make up` again.

`make` applies the Mac settings (no sleep, restart after power loss, Spotlight off on the drive, OrbStack memory cap, `tailscale serve` for Jellyfin), installs the Jellyfin LaunchAgent and starts the stack.

## Daily use

| Command | Does |
|---|---|
| `make up` | Start or converge everything, re-running init, setup and recyclarr |
| `make down` | Stop the containers |
| `make ps` | Status, including one-shot exit codes |
| `make logs s=sonarr` | Follow logs (omit `s` for all) |
| `make setup` | Re-run only the wiring |
| `make pull` | Pull the pinned images |
| `make secrets` | Edit the encrypted secrets |

## URLs

| Service | Tailnet | On the Mac |
|---|---|---|
| Jellyfin | `https://macmini.<tailnet>` | `localhost:8096` |
| Homepage | `https://home.<tailnet>` | `localhost:3000` |
| Seerr | `https://requests.<tailnet>` | `localhost:5055` |
| Sonarr, Radarr, Prowlarr, Bazarr | `https://sonarr.<tailnet>` etc. | `8989`, `7878`, `9696`, `6767` |
| qBittorrent | `https://qbit.<tailnet>` | `localhost:8080` |
| TSDProxy | `https://tsdproxy.<tailnet>` | `localhost:8088` |

Login everywhere: `admin` and `ADMIN_PASSWORD` from `make secrets`.

## Debugging

- `make ps` first: a failed `medialab-init` or `medialab-setup` shows its exit code; `make logs s=setup` shows which step failed.
- Native Jellyfin: `tail -f ~/Library/Logs/jellyfin.log` and `launchctl print gui/$(id -u)/org.jellyfin.server`. It only runs while `DATA_DIR` exists.
- `dependency failed to start: container warp is unhealthy`: WARP (the ISP-block bypass) is not connected. autoheal restarts it within a minute; check with `docker exec warp curl -s --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep warp=` (expect `warp=on`), then `make up` again. Still stuck: `make down`, delete `config/warp` (forces a fresh WARP registration), `make up`.
- Containers refuse to start while the media drive is unmounted; plug it in and they recover on their own.
- Hardlinks (imports must not copy): `docker exec radarr sh -c 'touch /data/torrents/movies/.t && ln -f /data/torrents/movies/.t /data/media/movies/.t && stat -c %h /data/media/movies/.t; rm -f /data/*/movies/.t'` prints `2`.
- Reset one app: `make down`, delete `config/<app>`, `make up`.

## Updating and rolling back

Bump an image tag in the group's `compose.yaml`, then `make pull up`. To roll back, `git revert` the commit and `make up`.
