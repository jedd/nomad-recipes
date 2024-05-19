
// paperless-ngx - personal document management system
//   with redis, postgresql database, a postgresql backup (daily) script, and tika/gotenberg

// Changes from previous version(s):
//  -  using nomad docker-plugin volumes so I can use absolute paths without creating host_volumes
//  -  tika and gotenberg have been enabled, but not heavily tested - a simple .odt (openoffice)
//       format file has been processed successfully.
//  -  the db-backup container hasn't been tested well, especially rollback / recovery - the intent
//       is that the whole persistent datastore location is periodically snapshotted outside the job.
//  -  email (incoming, or outgoing) does not work, and probably will remain a low priority for me.

// Naturally you'll need to change all my references to /opt/sharednfs/paperless-ngx to your
// persistent storage path.  Unfortunately Nomad jobs can't conveniently use variables for
// such things (short of going that 'via a template' wonky method).

// Similarly the loki target.


// Creating a superuser is needed on first run - this is done manually by
// summoning a shell in the primary container/task, and then:
// #  cd /usr/src/paperless/src
// #  python3 manage.py createsuperuser
// Then creating a 'root' user with a secret password.

variables {
  image_paperless = "ghcr.io/paperless-ngx/paperless-ngx:latest"
  image_redis = "docker.io/library/redis:7"
  image_postgresql = "docker.io/library/postgres:15"
  image_tika = "ghcr.io/paperless-ngx/tika:latest"
  image_gotenberg = "docker.io/gotenberg/gotenberg:7.8"
}


job "paperless-ngx" {
  datacenters = ["DG"]
  type = "service"

  # Only on the HA cluster
  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = "dg-hac-0[123]"
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
      port "port_tika" {
        to = 9998
      }
      port "port_gotenberg" {
        to = 3000
      }
    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }


    # TASK - broker = = = = = = = = = = = = = = = = = = = = = = = = =
    task "broker" {

      # The broker is effectively the redis cache

      driver = "docker"

      # Try to give Redis a moment while to terminate sanely.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
      }

      config {
        image = "${var.image_redis}"

        args = [
          "/etc/redis.conf",

          "--save",  "60 1",
          "--loglevel",  "warning",
        ]

        ports = ["port_paperless_redis"]

        # privileged = true

        volumes = [
          "local/redis.conf:/etc/redis.conf",
          "/opt/sharednfs/paperless-ngx/redis-data:/persistent/redis-data"
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

      # The db PostgreSQL

      driver = "docker"

      # Try to give PostgreSQL a little while to terminate sanely.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"


      env = {
        "PGDATA" = "/persistent/postgresql/data",
        "POSTGRES_DB" = "paperless"
        "POSTGRES_USER" = "paperless"
        "POSTGRES_PASSWORD" = "paperless"
      }

      config {
        image = "${var.image_postgresql}"

        ports = ["port_paperless_db"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/paperless-ngx/postgresql:/persistent/postgresql"
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

      # Paperless is the actual web-frontend + application backend

      driver = "docker"

      # Less useful than db (postgresql) above, but more polite than default SIGKILL,
      # and we may have some tasks mid-flight.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {

        # Only enable these on first run, and only if you can't or don't want
        # to use the createsuperuser script from within the container (once)..
        # "PAPERLESS_ADMIN_USER"      = "root",
        # "PAPERLESS_ADMIN_PASSWORD"  = "bigsecret",

        "PAPERLESS_REDIS"  = "redis://${NOMAD_ADDR_port_paperless_redis}",

        "PAPERLESS_DBENGINE" = "postgresql",

        "PAPERLESS_DBHOST" = "${NOMAD_IP_port_paperless_db}",
        "PAPERLESS_DBPORT" = "${NOMAD_HOST_PORT_port_paperless_db}",

        "PAPERLESS_DBUSER" = "paperless",
        "PAPERLESS_DBPASS" = "paperless",
        "PAPERLESS_DBNAME" = "paperless",

        "PAPERLESS_URL" = "http://paperless.obs.int.jeddi.org",

        # Because we're using NFS, we can't use inotify - so we need to use these
        # trio of settings, with a fair bit of delay as we're ALSO sending pdf's
        # over the wifi network, and larger documents combined with default settings
        # for these may result in abandoned pdf's in the ./consume/ directory.
        # (Default retry configuration is way aggressive - 5 retries but with only
        # 5s delay between those retries, and we can easily exceed 25s for a file
        # to be in transit and growing on disk.)
        #
        # Here we are setting 8 retries, with 30s delays, with a basic 60s polling interval.
        #
        "PAPERLESS_CONSUMER_POLLING_RETRY_COUNT"   = "8",
        "PAPERLESS_CONSUMER_POLLING_DELAY"         = "30",
        "PAPERLESS_CONSUMER_POLLING"               = "60",

        # This is preferred as it auto-tags files with the path - eg, consume/foo/bar/my-file.pdf,
        # would be imported with 'foo' and 'bar' tags.
        "PAPERLESS_CONSUMER_RECURSIVE"       = "true",
        "PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS" = "true",

        "PAPERLESS_CONSUMPTION_DIR"  = "/persistent/consume",
        "PAPERLESS_DATA_DIR"         = "/persistent/data",
        "PAPERLESS_TRASH_DIR"        = "/persistent/trash",
        "PAPERLESS_MEDIA_ROOT"       = "/persistent/media",
        "PAPERLESS_LOGGING_DIR"      = "/persistent/log",

        "PAPERLESS_TIKA_ENABLED" = "1",
        "PAPERLESS_TIKA_ENDPOINT" = "http://${NOMAD_ADDR_port_tika}",
        "PAPERLESS_TIKA_GOTENBERG_ENDPOINT" = "http://${NOMAD_ADDR_port_gotenberg}",

        "PAPERLESS_TIME_ZONE" = "Australia/Sydney",

        # On smaller systems, or even in the case of Very Large Documents, the consumer may
        # explode, complaining about how it's "unable to extend pixel cache". In such cases,
        # try setting this to a reasonably low value, like 32. The default is to use whatever
        # is necessary to do everything without writing to disk, and units are in megabytes.
        # "PAPERLESS_CONVERT_MEMORY_LIMIT" = 32,

      }

      config {
        image = "${var.image_paperless}"

        ports = ["port_paperless"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/paperless-ngx/consume:/persistent/consume",
          "/opt/sharednfs/paperless-ngx/data:/persistent/data",
          "/opt/sharednfs/paperless-ngx/trash:/persistent/trash",
          "/opt/sharednfs/paperless-ngx/media:/persistent/media",
          "/opt/sharednfs/paperless-ngx/log:/persistent/log",
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
        cpu = 1600
        memory = 1500
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


    # task postgresql-backup = = = = = = = = = = = = = = = = = = = = = = = = =
    task "db-backup" {
      
      # db-backup is a custom instance using PostgreSQL image, but only for the client, to perform periodic backups.

      driver = "docker"

      kill_signal = "SIGTERM"      

      config {
        image = "${var.image_postgresql}"

        command = "/backup-looper.sh"

        volumes = [
          "local/backup-looper.sh:/backup-looper.sh",
          "/opt/sharednfs/paperless-ngx/BACKUPS/db:/persistent/BACKUPS",
        ]

        logging {
          type = "loki"
          config {
            loki-url = "http://loki.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME},env=test"
          }
        }

      }

      env = {
        # It's just easier if we have local timezone inside the container.
        "TZ" = "Australia/Sydney",
      }

      resources {
        cpu = 200
        memory = 200
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
echo {{ env "NOMAD_ADDR_port_paperless_db" }}:paperless:paperless:paperless > ~/.pgpass

# Must be set to limited rights or else it ignores the file.
chmod 600 ~/.pgpass

while [ 1 ]
do
  # Sleep first, as the database is typically not ready on instantiation anyway
  sleep 1h

  HOUR=`date "+%H"`
  TARGETFILE=paperless_postgresql_db_backup_`date "+%a-%H"`H.sql

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
            -d paperless                                      \
            -U paperless                                      \
            -h {{ env "NOMAD_HOST_IP_port_paperless_db" }}    \
            -p {{ env "NOMAD_HOST_PORT_port_paperless_db" }}       

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


    # TASK - tika  = = = = = = = = = = = = = = = = = = = = = = = = =
    task "tika" {

      # Tika is used to parse Office documents (docx, odt, etc).  It is tightly coupled with Gotenberg.

      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
      }

      config {
        image = "${var.image_tika}"
        
        ports = ["port_tika"]

        # privileged = true

        volumes = [ ]

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
        memory = 500
        memory_max = 1024
      }

    } // end-task tika


    # TASK - gotenberg  = = = = = = = = = = = = = = = = = = = = = = = = =
    task "gotenberg" {

      # gotenberg is an API for PDF files - it is tightly coupled with Tika

      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
      }

      config {
        image = "${var.image_gotenberg}"
        
        ports = ["port_gotenberg"]

        # privileged = true

        volumes = [ ]

        command = "gotenberg"

        args = [
          "--chromium-disable-javascript=true",
          "--chromium-allow-list=file:///tmp/.*",
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
        memory = 500
        memory_max = 1024
      }

    } // end-task gotenberg

  }
}
