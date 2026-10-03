# maclab

Personal Mac mini homelab, one folder per stack (`medialab/`). Single user, no sharing concerns.

## Rules

- Reuse before writing: an existing tool, label convention or maintained library (Recyclarr, Homepage/TSDProxy labels, pyarr, qbittorrent-api) beats custom code. Search the web for the current best practice before adding anything.
- Keep code short and flat; add a comment only for a non-obvious gotcha.
- Every tunable lives in `<stack>/.env`; secrets live only in the sops-encrypted `<stack>/secrets.env`.
- Pin exact image tags and Python dependency versions; bumping one is a deliberate commit.
- `make up` converges: `init` (pre-start files) and `setup` (API wiring) are idempotent and safe to re-run.
- Each app group is a folder with its `compose.yaml` and config files, included from `<stack>/compose.yaml` with `project_directory: .`, so every path is relative to the stack folder.
- Media drive mounts use `create_host_path: false` so a missing drive fails loudly instead of filling the internal SSD.
- Verify a change by running the stack and exercising the changed path.
