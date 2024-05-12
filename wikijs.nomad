
// wiki-js - small personal wiki
//   three tasks - the wiki (wiki.js), the database (postgresql), and a backup job (perhaps not needed)



variables {
  image_wikijs = "ghcr.io/requarks/wiki:2.5.302"
  image_postgresql = "docker.io/library/postgres:15"
}


job "wikijs" {
  datacenters = ["DG"]
  type = "service"

  # Only on the HA cluster
  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = "dg-hac-0[123]"
  }

  group "wikijs" {
    network {
      port "port_wikijs" {
        to = 3000
      }
      port "port_wikijs_https" {
        to = 3443
      }
      port "port_wikijs_db" {
        to = 5432
      }
    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }


    # TASK - db = = = = = = = = = = = = = = = = = = = = = = = = =
    task "db" {
      # The db PostgreSQL
      driver = "docker"
			user = "postgres:postgres"

      # Try to give PostgreSQL a little while to terminate sanely.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"


      env = {
        "PGDATA" = "/persistent/postgresql/data",
        "POSTGRES_DB" = "wikijs"
        "POSTGRES_USER" = "wikijs"
        "POSTGRES_PASSWORD" = "wikijs"
      }

      config {
        image = "${var.image_postgresql}"

        ports = ["port_wikijs_db"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/wikijs/postgresql:/persistent/postgresql"
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
        cpu = 100
        memory = 100
        memory_max = 1024
      }

      service {
        name = "http"
        port = "port_wikijs_db"

#        check {
#          type = "http"
#          port = "port_wikijs_db"
#          path = "/"
#          interval = "30s"
#          timeout = "5s"
#        }

      }
    } // end-task db


    # TASK - wikijs = = = = = = = = = = = = = = = = = = = = = = = = =
    task "wikijs" {
      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        # DB_TYPE : Type of database (mysql, postgres, mariadb, mssql or sqlite)
				"DB_TYPE" = "postgres"

        "DB_HOST" = "${NOMAD_IP_port_wikijs_db}",
        "DB_PORT" = "${NOMAD_HOST_PORT_port_wikijs_db}",
				"DB_USER" = "wikijs",
				"DB_PASS" = "wikijs",
				"DB_NAME" = "wikijs",
      }

      config {
        image = "${var.image_wikijs}"

				# This is of dubious benefit, and occasionally conflicts with Traefik
        dns_servers = ["192.168.27.123"]
				# Might not be needed.
        hostname = "wikijs"

        ports = ["port_wikijs", "port_wikijs_https"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/wikijs/data/content:/wiki/data/content",
          "/opt/sharednfs/wikijs/config:/config",
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
        cpu = 600
        memory = 200
        memory_max = 2500
      }

      service {
        name = "wikijs"
        port = "port_wikijs"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.wikijs.entrypoints=http,https",
          "traefik.http.routers.wikijs.rule=Host(`wikijs.obs.int.jeddi.org`)",
          "traefik.http.routers.wikijs.tls=false"
        ]      

#        check {
#          type = "http"
#          port = "port_wikijs"
#          path = "/"
#          interval = "30s"
#          timeout = "5s"
#        }

      }
    } // end-task wikijs


    # task postgresql-backup = = = = = = = = = = = = = = = = = = = = = = = = =
    task "db-backup" {
      # db-backup is a custom instance using PostgreSQL image, but only for the client, to perform periodic backups.
			# Adopted from another job, but wiki.js might provide sufficient backup / dump scheduling to not need this.
      driver = "docker"
			user = "100:100"

      # Less useful than db or wikijs proper, but still nice to do.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      config {
        image = "${var.image_postgresql}"

        command = "/backup-looper.sh"

        volumes = [
          "local/backup-looper.sh:/backup-looper.sh",
          "/opt/sharednfs/wikijs/BACKUPS/db:/persistent/BACKUPS",
        ]

        logging {
          type = "loki"
          config {
            loki-url = "http://loki.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      env = {
        # It's just easier if we have local timezone inside the container.
        "TZ" = "Australia/Sydney",
      }

      resources {
        cpu = 100
        memory = 50
        memory_max = 300
      }

      service {
        name = "db-backup"
      }

      #  FILE:   backup-looper.sh
      #  This is our over-ridden entry point - we're just here for pg_dump but use the same 
      #  postgresql *server* image as we've already got it in cache on this host AND we get
      #  guaranteed client / server version alignment for free.
      template {
        data = <<EOH
#! /usr/bin/env bash

# Heavily opinionated backup script for small PostgreSQL database
#
# Sleep regularly, wake up to detect if we're in one of the right windows for the
# day (typically once a day, but can be adjusted below).  If so, perform a db dump
# then return to sleep.

TARGETDIR=/persistent/BACKUPS

if [ !  -d ${TARGETDIR} ]
then
  mkdir -p ${TARGETDIR}
fi

# Feeding a password to pg_dump is easier if we just use the ~/.pgpass convention
# in format:  hostname:port:database:username:password
echo {{ env "NOMAD_ADDR_port_wikijs_db" }}:wikijs:wikijs:wikijs > ~/.pgpass

# Must be set to limited rights or else it ignores the file.
chmod 600 ~/.pgpass

while [ 1 ]
do
  # Sleep first, as the database is typically not ready on instantiation anyway
  sleep 1h

  HOUR=`date "+%H"`
  TARGETFILE=wikijs_postgresql_db_backup_`date "+%a-%H"`H.sql

  # Multi-value alternative:
  # if [ ${HOUR} -eq 08 ] || [ ${HOUR} -eq 16 ] || [ ${HOUR} -eq 23 ] 

  # Daily option:
  if [ ${HOUR} -eq 23 ]
  then
    # First - remove the 1-week old archive
    rm ${TARGETDIR}/${TARGETFILE}.gz

    # pg_dump requires the following params despite them being in pgpass - pgpass is a pattern
    # matching file only, and password is retrieved when user/db/addr matches.
    pg_dump -f ${TARGETDIR}/${TARGETFILE}                     \
            -Fc                                               \
            -d wikijs                                         \
            -U wikijs                                         \
            -h {{ env "NOMAD_HOST_IP_port_wikijs_db" }}       \
            -p {{ env "NOMAD_HOST_PORT_port_wikijs_db" }}       

    # The -Fc format is recommended - ostensibly it is compressed but in practice not optimally,
    # so we compress properly with gzip as the final step.
    gzip --best ${TARGETDIR}/${TARGETFILE}
  fi
done

EOH
        destination = "local/backup-looper.sh"
        perms = "755"
      }
    }    #  end-task db-backup

  }
}

