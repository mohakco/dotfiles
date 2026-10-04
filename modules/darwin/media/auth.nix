# Authelia (passkey login) gating the web apps through Caddy forward auth.
# Containers, because nixpkgs' Authelia web UI does not build on darwin.
{
  cfg,
  hostName,
}:
let
  domain = cfg.tailnet;
  authelia = "authelia:9091";
  secrets = {
    jwt = "AUTHELIA_JWT_SECRET";
    session = "AUTHELIA_SESSION_SECRET";
    storage = "AUTHELIA_STORAGE_KEY";
  };
in
rec {
  # Subdomain -> container upstream; each gets a tailnet name via TSDProxy.
  apps = {
    radarr = "radarr:7878";
    prowlarr = "prowlarr:9696";
    qbit = "qbittorrent:8080";
    requests = "seerr:5055";
  };
  # Subdomain -> upstream reachable without login (still tailnet-only).
  openApps = {
    home = "homepage:3000";
  };

  services = {
    authelia = {
      image = "authelia/authelia:4.39.28";
      container_name = "authelia";
      restart = "unless-stopped";
      command = [
        "--config"
        "/etc/authelia/configuration.yml"
      ];
      environment = {
        PUID = toString cfg.uid;
        PGID = "20";
        TZ = cfg.timeZone;
        AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE = "/secrets/jwt";
        AUTHELIA_SESSION_SECRET_FILE = "/secrets/session";
        AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "/secrets/storage";
      };
      volumes = [ "${cfg.stateDir}/authelia:/config" ];
      configs = [
        {
          source = "authelia";
          target = "/etc/authelia/configuration.yml";
        }
        {
          source = "authelia-users";
          target = "/etc/authelia/users.yml";
        }
      ]
      ++ map (name: {
        source = "authelia-${name}";
        target = "/secrets/${name}";
      }) (builtins.attrNames secrets);
    };

    caddy = {
      image = "caddy:2.11.4-alpine";
      container_name = "caddy";
      restart = "unless-stopped";
      volumes = [ "${cfg.stateDir}/caddy:/data" ];
      configs = [
        {
          source = "caddyfile";
          target = "/etc/caddy/Caddyfile";
        }
      ];
    };
  };

  configs = {
    authelia.content = builtins.toJSON {
      server.address = "tcp://:9091/";
      log.level = "info";
      theme = "auto";
      authentication_backend = {
        file = {
          path = "/etc/authelia/users.yml";
          watch = false;
        };
        password_reset.disable = true;
      };
      webauthn = {
        display_name = hostName;
        enable_passkey_login = true;
      };
      access_control = {
        default_policy = "deny";
        rules = [
          # Unused name: Authelia only shows passkey (WebAuthn) registration once some rule needs two_factor.
          {
            domain = [ "2fa.${domain}" ];
            policy = "two_factor";
          }
          {
            domain = [ "*.${domain}" ];
            policy = "one_factor";
          }
        ];
      };
      session.cookies = [
        {
          inherit domain;
          authelia_url = "https://auth.${domain}";
        }
      ];
      storage.local.path = "/config/db.sqlite3";
      # No mail server: one-time codes (e.g. to register a passkey) land in this file.
      notifier.filesystem.filename = "/config/notification.txt";
    };

    "authelia-users".content = builtins.toJSON {
      users.${cfg.auth.user} = {
        displayname = cfg.auth.user;
        inherit (cfg.auth) email;
        password = "\${AUTHELIA_PASSWORD_HASH}";
      };
    };

    # TSDProxy terminates TLS, so Caddy sees plain HTTP and must tell Authelia the real scheme.
    caddyfile.content = ''
      {
        admin off
        auto_https off
        http_port 8099
      }

      http://auth.${domain} {
        reverse_proxy ${authelia} {
          header_up X-Forwarded-Proto https
        }
      }
    ''
    + builtins.concatStringsSep "" (
      builtins.attrValues (
        builtins.mapAttrs (name: upstream: ''

          http://${name}.${domain} {
            forward_auth ${authelia} {
              uri /api/authz/forward-auth
              header_up X-Forwarded-Proto https
              copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
            }
            reverse_proxy ${upstream}
          }
        '') apps
      )
      ++ builtins.attrValues (
        builtins.mapAttrs (name: upstream: ''

          http://${name}.${domain} {
            reverse_proxy ${upstream}
          }
        '') openApps
      )
    );
  }
  // builtins.listToAttrs (
    map (name: {
      name = "authelia-${name}";
      value.content = "\${${secrets.${name}}}";
    }) (builtins.attrNames secrets)
  );

  envSecrets = builtins.attrValues secrets ++ [ "AUTHELIA_PASSWORD_HASH" ];
}
