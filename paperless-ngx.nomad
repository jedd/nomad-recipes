
// paperless-ngx - personal document management system

// 2023-07-17 - current state is that the system works, but has not been heavily tested:
//
//   You need to create a superuser (see below) or adjust the env 
//   variables (see long way below).
// 
//   You need a persistent volume - mine is called 'vol_paperless_ngx' and it lives on 
//   NFS, so inotify does NOT work for me.
//
//   The ./trash/ folder is NOT being respected, and I don't know why - it's not a 
//   priority for me, and doesn't seem to break anything.
//
//   I don't know how much I trust the postgresql shutdown (SIGTERM), or indeed 
//   redis (that shouldn't be breakable) or paperless itself (no idea).
//
//   Email doesn't work at all, haven't even tried getting that routing into this.


// Creating a superuser is needed on first run - this is done manually by
// summoning a shell in the primary container/task as follows, or use the
// PAPERLESS_ADMIN_USER (and _PASSWORD) in the paperless task below.
// #  cd /usr/src/paperless/src
// #  python3 manage.py createsuperuser
// Then creating a 'root' user with a secret password.

job "paperless-ngx" {
  datacenters = ["DG"]
  type = "service"

  # Only on the HA cluster
  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    # value = "dg-hac-0[123]"
    value = "dg-hac-0[1]"
  }

  group "paperless-ngx" {
    network {
      port "port_paperless" {
        to = 8000
      }
      port "port_paperless_redis" {
        to = 6379
      }
      port "port_paperless_db" {
        to = 5432
      }
    }

    volume "vol_paperless_ngx"  {
      type = "host"
      source = "vol_paperless_ngx"
      read_only = false
    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

#   constraint {
#     attribute = "${attr.unique.hostname}"
#     operator = "regexp"
#     value = "dg-hac-0[123]"
#   }


    # TASK - broker = = = = = = = = = = = = = = = = = = = = = = = = =
    task "broker" {
      driver = "docker"

      # Try to give Redis a moment while to terminate sanely.
      kill_timeout = "10s"
      kill_signal = "SIGTERM"

      volume_mount {
        volume = "vol_paperless_ngx"
        destination = "/persistent"
        read_only = false
      }

      env = {
      }

      config {
        image = "docker.io/library/redis:7"

        args = [
          "/etc/redis.conf",

          "--save",  "60 1",
          "--loglevel",  "warning",
        ]

        dns_servers = ["192.168.27.123"]

        ports = ["port_paperless_redis"]

        volumes = [
          "local/redis.conf:/etc/redis.conf",
        ]

        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 200
        memory = 200
        memory_max = 1024
      }

      service {
        name = "redis"
        port = "port_paperless_redis"

#        check {
#          type = "http"
#          port = "port_paperless_broker"
#          path = "/"
#          interval = "30s"
#          timeout = "5s"
#        }
      }

      template {
        data = <<EOH
DIR /persistent/redis-data
EOH
        destination = "local/redis.conf"
      }
    } // end-task broker


    # TASK - db = = = = = = = = = = = = = = = = = = = = = = = = =
    task "db" {
      driver = "docker"

      # Try to give PostgreSQL a little while to terminate sanely.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      volume_mount {
        volume = "vol_paperless_ngx"
        destination = "/persistent"
        read_only = false
      }

      env = {
        "PGDATA" = "/persistent/postgresql/data",
        "POSTGRES_DB" = "paperless"
        "POSTGRES_USER" = "paperless"
        "POSTGRES_PASSWORD" = "bigsecret"
      }

      config {
        image = "docker.io/library/postgres:15"

        dns_servers = ["192.168.27.123"]

        ports = ["port_paperless_db"]

        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      resources {
        cpu = 200
        memory = 200
        memory_max = 1024
      }

      service {
        name = "http"
        port = "port_paperless_db"
#        check {
#          type = "http"
#          port = "port_paperless_db"
#          path = "/"
#          interval = "30s"
#          timeout = "5s"
#        }
      }
    } // end-task db


    # TASK - paperless = = = = = = = = = = = = = = = = = = = = = = = = =
    task "paperless" {
      driver = "docker"

      # Less useful than db (postgresql) above, but more polite than default SIGKILL,
      # and we may have some tasks mid-flight.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      volume_mount {
        volume = "vol_paperless_ngx"
        destination = "/persistent"
        read_only = false
      }

      env = {

        # Only enable these on first run, and only if you can't or don't want
        # to use the createsuperuser script from within the container (once)..
        # "PAPERLESS_ADMIN_USER"      = "root",
        # "PAPERLESS_ADMIN_PASSWORD"  = "bigsecret",

        "PAPERLESS_REDIS"  = "redis://${NOMAD_ADDR_port_paperless_redis}",

        "PAPERLESS_DBHOST" = "${NOMAD_IP_port_paperless_db}",
        "PAPERLESS_DBPORT" = "${NOMAD_HOST_PORT_port_paperless_db}",

        "PAPERLESS_DBUSER" = "paperless",
        "PAPERLESS_DBPASS" = "bigsecret",
        "PAPERLESS_DBNAME" = "paperless",

        "PAPERLESS_URL" = "http://paperless.obs.int.jeddi.org",

        # This is need IFF you don't have inotify (say, /persistent/consume is on NFS).
        # Defaults for PAPERLESS_CONSUMER_POLLING_RETRY and _DELAY are both 5s.
        "PAPERLESS_CONSUMER_POLLING"   = "10",

        # This is preferred as it auto-tags files with the path - eg, consume/foo/bar/my-file.pdf,
        # would be imported with 'foo' and 'bar' tags.
        "PAPERLESS_CONSUMER_RECURSIVE"       = "true",
        "PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS" = "true",

        "PAPERLESS_CONSUMPTION_DIR"  = "/persistent/consume",
        "PAPERLESS_DATA_DIR"         = "/persistent/data",
        "PAPERLESS_TRASH_DIR"        = "/persistent/trash",
        "PAPERLESS_MEDIA_ROOT"       = "/persistent/media",
        "PAPERLESS_LOGGING_DIR"      = "/persistent/log",

      }

      config {
        image = "ghcr.io/paperless-ngx/paperless-ngx:latest"

        dns_servers = ["192.168.27.123"]

        ports = ["port_paperless"]

        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      resources {
        cpu = 700
        memory = 1200
        memory_max = 2500
      }

      service {
        name = "paperless"
        port = "port_paperless"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.paperless.entrypoints=http",
          "traefik.http.routers.paperless.rule=Host(`paperless.obs.int.jeddi.org`)",
          "traefik.http.routers.paperless.tls=false"
        ]      

#        check {
#          type = "http"
#          port = "port_paperless"
#          path = "/"
#          interval = "30s"
#          timeout = "5s"
#        }
      }
    } // end-task paperless

  }
}
