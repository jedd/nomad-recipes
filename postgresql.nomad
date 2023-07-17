// jedd lab - vanilla postgresql image

job "postgresql" {
  datacenters = ["DG"]
  type        = "service"

  group "postgresql" {
    count = 1
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "port_postgresql"  {
        # NB - if we have PostgreSQL natively on the parent host, we'll
        #      need to remap the default port to something else.

        # NB - startup logs indicate that PostgreSQL binds to 0.0.0.0 on tcp/5432,
        #      however I'm only seeing it on public interface, not localhost, and
        #      not my docker network (192.168.31.1/24)

        # without traefik
        static = 5432
        # with traefik
        # to = 5432
      }
    }

    volume "vol_postgresql" {
      type            = "host"
      source          = "vol_postgresql"
      read_only       = false
    }

    # You WILL get these errors:
    #  chown: changing ownership of '/var/lib/postgresql/data/pgdata': Operation not permitted
    #  chmod: changing permissions of '/var/lib/postgresql/data/pgdata': Operation not permitted
    #  -- repeated for: /var/run/postgres
    #
    # The native docker image will run find on the same host with 'docker run postgres:12', but fail
    # with the above errors when running in Nomad ... for reasons.
    #
    # The problem is described here:
    #  https://github.com/docker-library/docs/blob/master/postgres/README.md#arbitrary---user-notes
    # 

    task "postgresql" {
      driver = "docker"

      # This solves the chmod changing permission / chown changing ownership Operation not permitted errors
      user = "postgres:postgres"

      config {
        image = "postgres:12"

        ports = ["port_postgresql"]

        # This solved the chmod for /var/run/postgres permission error, but could not be extended to
        # solve the user mapping related errors for /var/lib/... 
        # volumes = [
        #  "local/var-run:/var/run",
        # ]

        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      env = {
        "POSTGRES_USER"     = "postgres",
        "POSTGRES_PASSWORD" = "password",
        "PGDATA" = "/var/lib/postgresql/data/pgdata"
      }

      volume_mount {
        volume      = "vol_postgresql"
        destination = "/var/lib/postgresql"
        read_only   = false
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      service {
        name = "postgresql"

        port = "port_postgresql"

        check {
          name     = "PostgreSQL healthcheck"
          port     = "port_postgresql"
          type     = "tcp"
          path     = "/ready"
          interval = "20s"
          timeout  = "5s"
          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }

      }
    }

  }
}
