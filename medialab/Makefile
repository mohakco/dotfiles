include .env
export

SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
PLIST := $(HOME)/Library/LaunchAgents/org.jellyfin.server.plist
dc = sops exec-env secrets.env 'docker compose $(1)'

.PHONY: all up down ps logs setup pull secrets mac jellyfin

all: mac up

up: secrets.env
	@test -d "$(MEDIA_VOLUME)" || { echo "$(MEDIA_VOLUME) not found, is the drive mounted?"; exit 1; }
	mkdir -p "$(DATA_DIR)"
	$(call dc,up -d --remove-orphans)
	@curl -sf localhost:5055/api/v1/status | grep -q '"restartRequired":true' && docker restart seerr || true

down:
	$(call dc,down)

ps:
	$(call dc,ps -a)

logs:
	$(call dc,logs -f --tail=200 $(s))

setup:
	$(call dc,up init setup recyclarr)

pull:
	$(call dc,pull)

secrets.env:
	@test -n "$$TS_AUTHKEY" || { echo "First run needs a Tailscale auth key: TS_AUTHKEY=tskey-auth-... make"; exit 1; }
	@test -f "$(SOPS_AGE_KEY_FILE)" || { mkdir -p "$(dir $(SOPS_AGE_KEY_FILE))" && age-keygen -o "$(SOPS_AGE_KEY_FILE)"; }
	printf 'ADMIN_PASSWORD=%s\nSONARR_API_KEY=%s\nRADARR_API_KEY=%s\nPROWLARR_API_KEY=%s\nTS_AUTHKEY=%s\n' \
		$$(openssl rand -hex 10) $$(openssl rand -hex 16) $$(openssl rand -hex 16) $$(openssl rand -hex 16) "$$TS_AUTHKEY" > $@
	sops encrypt -i --age "$$(age-keygen -y "$(SOPS_AGE_KEY_FILE)")" $@

secrets: secrets.env
	sops edit $<

mac: jellyfin
	sudo pmset -a sleep 0 disksleep 0 autorestart 1
	sudo mdutil -i off "$(MEDIA_VOLUME)"
	touch "$(MEDIA_VOLUME)/.metadata_never_index"
	orb config set memory_mib 6144
	sudo "$$(command -v tailscale)" serve --bg --https=443 http://127.0.0.1:8096

jellyfin:
	mkdir -p "$(dir $(PLIST))" "$(HOME)/Library/Logs"
	sed -e 's|@HOME@|$(HOME)|g' -e 's|@DATA_DIR@|$(DATA_DIR)|g' macos/jellyfin.plist > "$(PLIST)"
	-launchctl bootout gui/$$(id -u)/org.jellyfin.server
	-pkill -x "Jellyfin Server"
	launchctl bootstrap gui/$$(id -u) "$(PLIST)"
