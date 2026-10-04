# Wiring that lives in the *arr databases: root folder, download client, sizes, indexers.
{ cfg }:
let
  q = cfg.quality;
  # Every HD quality gets the same MB/min band so releases fit the small drive.
  size = quality: {
    inherit quality;
    min = q.minMbPerMin;
    preferred = q.preferredMbPerMin;
    max = q.maxMbPerMin;
  };
in
{
  radarr.radarr = {
    base_url = "http://radarr:7878";
    api_key = "\${RADARR_API_KEY}";
    root_folders = [ "/data/media/movies" ];
    download_clients.data = [
      {
        name = "qBittorrent";
        type = "qbittorrent";
        enable = true;
        priority = 1;
        remove_completed_downloads = true;
        fields = {
          host = "qbittorrent";
          port = 8080;
          movie_category = "movies";
        };
      }
    ];
    media_management.minimumFreeSpaceWhenImporting = cfg.minFreeMb;
    quality_definition.qualities = map size [
      "HDTV-720p"
      "WEBDL-720p"
      "WEBRip-720p"
      "Bluray-720p"
      "HDTV-1080p"
      "WEBDL-1080p"
      "WEBRip-1080p"
      "Bluray-1080p"
      "Remux-1080p"
    ];
    # TRaSH "x265 (HD)": small x265 and YTS releases are what fit on the drive.
    custom_formats = [
      {
        trash_ids = [ "dc98083864ea246d05a42df0d05f81cc" ];
        assign_scores_to = [
          {
            name = "HD-1080p";
            score = 100;
          }
        ];
      }
    ];
  };

  prowlarr.prowlarr = {
    base_url = "http://prowlarr:9696";
    api_key = "\${PROWLARR_API_KEY}";
    tags = [
      "warp"
      "flaresolverr"
    ];
    # Tagged indexers go through these proxies: everything via WARP, Cloudflare sites via FlareSolverr.
    indexer_proxies.data = [
      {
        name = "WARP";
        type = "Socks5";
        tags = [ "warp" ];
        fields = {
          host = "warp";
          port = 1080;
        };
      }
      {
        name = "FlareSolverr";
        type = "FlareSolverr";
        tags = [ "flaresolverr" ];
        fields = {
          host = "http://flaresolverr:8191/";
          requestTimeout = 60;
        };
      }
    ];
    indexers.data = map (name: {
      inherit name;
      definition = name;
      enable = true;
      tags = [
        "warp"
      ]
      ++ (if builtins.elem name cfg.cloudflareIndexers then [ "flaresolverr" ] else [ ]);
    }) cfg.indexers;
    applications = {
      data = [
        {
          name = "Radarr";
          type = "Radarr";
          sync_level = "fullSync";
          fields = {
            prowlarrUrl = "http://prowlarr:9696";
            baseUrl = "http://radarr:7878";
            apiKey = "\${RADARR_API_KEY}";
          };
        }
      ];
      sync_indexers = true;
    };
  };
}
