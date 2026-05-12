
// soul cluster

// - slskd : client for Soulseek P2P network
// - SoulSync : automation for music discovery and organisation

// Locking to PY, and to py-hac-05 (where yarr.nomad lives) though they
// don't really inter-operate at all.
//
// slskd needs a fixed and forwarded public port (tcp/50030) - you can
// work around this problem, including via VPN, but doing that is left
// as an exercise for the reader. Your country's whims may vary.
//
// Using /localstore/soul/ - because they use sqlite3 under the hood,
// and that can be a bit fragile on NFS.

// Before first launch, setup persistent storage paths:
// ---------------------------------------------------paths
// py-hac-05:~#  mkdir -p /opt/localstore/soul/soulsync/{config,data,logs,downloads,transfer,staging}
// py-hac-05:~#  mkdir -p /opt/localstore/soul/slskd/{config,incomplete}
// py-hac-05:~#  chown -R 1000:1000 /opt/localstore/soul

// After first launch:
// ------------------
// slskd - has username / password of `slskd` and that should be changed via web ui.
//
// soul - change the file /opt/localstore/soul/soulsync/config/config.json - line 30
//        FROM     "slskd_url": "http://host.docker.internal:5030",
//        TO       "slskd_url": "https://slskd.obs.int.jeddi.org",


// == SLSKD ==
// 2026-04-25 = 0.25.1
// skopeo copy docker://ghcr.io/hotio/slskd:release-0.25.1   docker://registry.obs.int.jeddi.org/slskd:release-0.25.1

// == SOULSYNC ==
// CHECK CURRENT VERSION AT:  https://github.com/Nezreka/SoulSync/releases
//
// 2026-04-25 = 2.3
// skopeo copy docker://registry.hub.docker.com/boulderbadgedad/soulsync:2.3  docker://registry.obs.int.jeddi.org/soulsync:2.3
// 2026-04-27 = 2.4.0
// skopeo copy docker://ghcr.io/nezreka/soulsync:2.4.0 docker://registry.obs.int.jeddi.org/soulsync:2.4.0
// 2026-05-04 = 2.4.1
// skopeo copy docker://ghcr.io/nezreka/soulsync:2.4.1 docker://registry.obs.int.jeddi.org/soulsync:2.4.1
// 2026-05-12 = 2.5.0
// skopeo copy docker://ghcr.io/nezreka/soulsync:2.5.0 docker://registry.obs.int.jeddi.org/soulsync:2.5.0

# Variables  = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
variable "nomad_dc" {
  type = string
  default = ""
  description = "DC to constrain and run this job - it should be defined in your shell environment"
}

locals {
  image_slskd = "registry.obs.int.jeddi.org/slskd:release-0.25.1"
  image_soulsync = "registry.obs.int.jeddi.org/soulsync:2.5.0"

  # This job will ONLY ever run at PY
  host_constraint  = var.nomad_dc == "PY" ? "py-hac-05" : "nope"

  loki_url = "https://loki-rwb.obs.int.jeddi.org/loki/api/v1/push"

  # Common environment variables
  puid = "1000"
  pgid = "1000"
  timezone = "Australia/Sydney"
}

# Job  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
job "soul" {
  datacenters = [ var.nomad_dc ]

  type = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = local.host_constraint
  }

  update {
    stagger = "30s"
    max_parallel = 1
  }


  # GROUP - slskd = = = = = = = = = = = = = = = = = = = = = = = = = =
  group "slskd" {

    network {
      port "port_slskd_http" {
        to = 5030
      }
      port "port_slskd_https" {
        to = 5031
      }
      port "port_slskd_api" {
        static = 50300
        to = 50300
      }
    }

    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay = "25s"
      mode = "delay"
    }

    # TASK - slskd = = = = = = = = = = = = = = = = = = = = = = = = =
    task "slskd" {
      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        "PUID" = local.puid
        "PGID" = local.pgid
        "TZ" = local.timezone

        # This lets us modify configuration via the web UI
        "SLSKD_REMOTE_CONFIGURATION" = "true"

        # Default is not specified, but [None, Warning, Info, Debug] are available
        "SLSKD_SLSK_DIAG_LEVEL" = "Warning"

        # Enable metrics at /metrics - and disable auth (default is enabled)
        "SLSKD_METRICS" = "true"
        "SLSKD_METRICS_NO_AUTH" = "true"

        # Do NOT specify the `APP_DIR` despite some documentation saying you can or should,
        # because it looks in that directory for the executable 'slskd'.  Refer the volume
        # mount below for some more context.
        # "APP_DIR" = "/data"
      }

      config {
        image = local.image_slskd
        image_pull_timeout = "10m"

        ports = [
          "port_slskd_http",
          "port_slskd_https",
          "port_slskd_api",
        ]

        volumes = [
          "/etc/localtime:/etc/localtime:ro",

          # All persistent storage should go here - noting that `APP_DIR` is separate,
          # despite documentation for docker indicating that's a volume mount point.
          # So - don't mount to /app (or anything else that you line up with APP_DIR),
          # instead just mount to /config - the default path for `CONFIG_DIR` within the
          # container.
          "/opt/localstore/soul/slskd/config:/config",

          # This should be okay to be ephemeral (and not specified anywhere), but slskd seems
          # disinclined to auto-create it. Persistence is not much use, but also very low-cost.
          "/opt/localstore/soul/slskd/incomplete:/app/incomplete",

          # These are my things I'm sharing
          "/hub/pub/audio/music/songs:/sharing/songs:ro",
          "/hub/pub/audio/music/albums:/sharing/albums:ro",

          # These are shared - mounted by both slskd and soulsync
          "/opt/localstore/soul/soulsync/downloads:/app/downloads",
        ]

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      resources {
        cpu = 500
        memory = 600
        memory_max = 1000
      }

      service {
        name = "slskd"
        port = "port_slskd_http"

        tags = [
           "traefik.enable=true",
           "traefik.http.routers.slskd.rule=Host(`slskd.obs.int.jeddi.org`)",
           "traefik.http.routers.slskd.tls=true",
           "traefik.http.routers.slskd.entrypoints=https",
        ]

        #check {
        #  name     = "slskd-health"
        #  type     = "http"
        #  path     = "/ping"
        #  interval = "60s"
        #  timeout  = "10s"
        #  initial_status = "passing"
        #}
      }
    }
  }  // end-group slskd


  # GROUP - soulsync = = = = = = = = = = = = = = = = = = = = = = = = = =
  group "soulsync" {

    network {
      port "port_soul_http" {
        to = 8008
      }
      port "port_soul_spotify" {
        to = 8888
      }
      port "port_soul_tidal" {
        to = 8889
      }
    }

    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay = "25s"
      mode = "delay"
    }

    # TASK - soulsync = = = = = = = = = = = = = = = = = = = = = = = = =
    task "soulsync" {
      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        "PUID" = local.puid
        "PGID" = local.pgid
        "TZ" = local.timezone

        # Default is INFO which is a bit too chatty.
        "SOULSYNC_LOG_LEVEL" = "WARN"
      }

      config {
        image = local.image_soulsync
        image_pull_timeout = "10m"

        ports = [
          "port_soul_http",
          "port_soul_spotify",
          "port_soul_tidal",
        ]

        volumes = [
          "/etc/localtime:/etc/localtime:ro",

          # They use /app for shipping their data too, so these are all manually setup
          "/opt/localstore/soul/soulsync/config:/app/config",
          "/opt/localstore/soul/soulsync/logs:/app/logs",
          "/opt/localstore/soul/soulsync/downloads:/app/downloads",
          "/opt/localstore/soul/soulsync/Transfer:/app/Transfer",
          "/opt/localstore/soul/soulsync/Staging:/app/Staging",

          # The sqlite3 database lives here - it was originally with the rest, but on
          # 2026-04-27 in an attempt to reduce the number of 'can't write to the database'
          # errors in the log files, moved to dedicated SSD-based LV, like immich's.
          # "/opt/localstore/soul/soulsync/data:/app/data",
          "/opt/localstore-ssd/soul/soulsync/data:/app/data",

          # Soulsync needs to know the two directories I'm sharing (in slskd) mostly
          # so it knows what's missing from my collection.
          # Mounted at /library not /sharing here, though
          "/hub/pub/audio/music/songs:/library/songs:ro",
          "/hub/pub/audio/music/albums:/library/albums:ro",

          # Experimenting with a read-write location to properly scan content
          # "/opt/localstore/soul/soulsync/albums-copy-subset-read-write:/library/albumsrw",
          "/opt/localstore/soul/soulsync/albums-copy-subset-read-write:/music",
        ]

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      resources {
        cpu = 500
        memory = 3000
        memory_max = 6000
      }

      service {
        name = "soul"
        port = "port_soul_http"

        tags = [
           "traefik.enable=true",
           "traefik.http.routers.soul.rule=Host(`soulsync.obs.int.jeddi.org`)",
           "traefik.http.routers.soul.entrypoints=https,http",
        ]
      }

      service {
        name = "soulspotify"
        port = "port_soul_spotify"

        tags = [
           "traefik.enable=true",
           "traefik.http.routers.soul-spotify.rule=Host(`soulspotify.obs.int.jeddi.org`)",
           "traefik.http.routers.soul-spotify.entrypoints=https,http",
        ]
      }
    }

  }  // end-group soul
} // end-job

