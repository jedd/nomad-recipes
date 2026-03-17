
// Paperless NGX - Jedd's data

// 2025-03 - DG / PY variant

// This job assumes very little - in my environment it was designed to run at
// either of two datacenters but pragmatically ends up being only at one.

// There's some smb exposure for sending data from the scanner directly
// ( I use a little portable Brother scanner that can send to an smb share. )

// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =


// paperless-ngx JEDD instance - personal document management system
//   with redis, postgresql database, a postgresql backup (daily) script, and tika/gotenberg

// Changes from previous version(s):
//  -  using nomad docker-plugin volumes so I can use absolute paths without creating host_volumes
//  -  tika and gotenberg have been enabled, but not heavily tested - a simple .odt (openoffice)
//       format file has been processed successfully.
//  -  the db-backup container hasn't been tested well, especially rollback / recovery - the intent
//       is that the whole persistent datastore location is periodically snapshotted outside the job.
//  -  email (incoming, or outgoing) does not work, and probably will remain a low priority for me.

// Installation (first run) instructions:
// After first (abortive) run - go into /opt/sharednfs/paperless-jedd - and chmod 777 the 8 directories
// that have been made - then stop/purge the job, and re-run it - it should start, and you can proceed.

// Creating a superuser is needed on first run - this is done manually by
// summoning a shell in the primary container/task, and then:
// #  cd /usr/src/paperless/src
// #  python3 manage.py createsuperuser
// Then creating a 'root' user with a secret password.

// 2024-11-17 - looking at backup options.
// The 'document_exporter' tool, in /usr/local/bin/ in the paperless task - can dump everything
// to a target directory.  It may not be useful, as there are multiple ways to generate backups.
//
// This is a way to perhaps run an exec inside a container (alloc / task) remotely, so potentially
// using cron on the host, to call into the container via nomad, eg:
//
//    nomad alloc exec -task paperless b1b41c02 /usr/local/bin/document_exporter
//
// However getting parameters to that command passed through nomad CLI remains elusive.

// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
variable "nomad_dc" {
  type = string
  default = "PY"
  description = "DC to constrain and run this job - it should be defined in your shell environment"
}


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
locals {

  # skopeo copy docker://ghcr.io/paperless-ngx/paperless-ngx:2.10.2 docker://registry.obs.int.jeddi.org/paperless-ngx:2.10.2
  # image_paperless = "dg-pan-01.int.jeddi.org:5000/paperless-ngx:2.10.2"
  # 2026-02-10 - upgrading from 2.10.2 to 2.20.6 - some breaking changes, but
  # most seem minor apart from a requirement to bump gotenberg (refer below).
  # image_paperless = "registry.obs.int.jeddi.org/paperless-ngx:2.10.2"
  image_paperless = "registry.obs.int.jeddi.org/paperless-ngx:2.20.6"

  # skopeo copy 
  #        docker://docker.io/library/redis:7 
  #        docker://registry.obs.int.jeddi.org/redis:7
  # image_redis = "docker.io/library/redis:7"
  image_redis = "registry.obs.int.jeddi.org/redis:7"

  # skopeo copy 
  #        docker://docker.io/library/postgres:15  
  #        docker://registry.obs.int.jeddi.org/postgres:15
  # image_postgresql = "docker.io/library/postgres:15"
  image_postgresql = "registry.obs.int.jeddi.org/postgres:15"

  # paperless guys set this up pre-2024-05 for more arch support, but apache
  # support changed 2024-05 and paperless recommends going back to apache tika
  # image_tika = "docker.io/apache/tika:2.9.2.1"
  # skopeo copy 
  #        docker://docker.io/apache/tika:2.9.2.1  
  #        docker://registry.obs.int.jeddi.org/tika:2.9.2.1
  # 2026-02-10 - upgrading from 2.9.2.1 to 3.2.3.0 - might as well, with the gotenberg and paperless 
  # upgrades. 3.2.3.0 is 5 months old at this time.
  # image_tika = "registry.obs.int.jeddi.org/tika:2.9.2.1"
  image_tika = "registry.obs.int.jeddi.org/tika:3.2.3.0"

  # image_gotenberg = "docker.io/gotenberg/gotenberg:7.8"
  # skopeo copy 
  #        docker://docker.io/gotenberg/gotenberg:7.8  
  #        docker://registry.obs.int.jeddi.org/gotenberg:7.8
  # image_gotenberg = "registry.obs.int.jeddi.org/gotenberg:7.8" 
  # 2026-02-10 - upgrading from 7.8 to 8.26.0 - as a pre-requisite for paperless 2.10.2 to 2.11.0
  # no other breaking changes for paperless-2.10.2 to paperless-2.20.6
  # image_gotenberg = "registry.obs.int.jeddi.org/gotenberg:7.8" 
  image_gotenberg = "registry.obs.int.jeddi.org/gotenberg:8.26.0"

  # skopeo copy 
  #        docker://docker.io/hashicorp/nomad:1.11  
  #        docker://registry.obs.int.jeddi.org/nomad:1.11
  image_nomad = "registry.obs.int.jeddi.org/nomad:1.11"

  # This will lock us into PY - can be reverted if ever needed.
  # host_constraint = var.nomad_dc == "DG" ? "dg-hac-*" : "py-hac-*"
  host_constraint = "py-hac-*"

  # loki_url = "https://loki.obs.int.jeddi.org/loki/api/v1/push"
  loki_url = "https://loki-rwb.obs.int.jeddi.org/loki/api/v1/push"
}


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
job "paperless-jedd" {
  datacenters = [ var.nomad_dc ]

  type = "service"

  # Only on the HA cluster
  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = local.host_constraint
  }

  group "paperless-jedd" {
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
      delay = "30s"
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
        image = local.image_redis
        image_pull_timeout = "10m"

        args = [
          "/etc/redis.conf",

          "--save",  "60 1",
          "--loglevel",  "warning",
        ]

        ports = ["port_paperless_redis"]

        # privileged = true

        volumes = [
          "local/redis.conf:/etc/redis.conf",
          "/opt/sharednfs/paperless-jedd/redis-data:/persistent/redis-data"
        ]

        logging  {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 100
        memory = 250
        memory_max = 1500
      }

      service {
        name = "redis-ppljedd"
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
        image = local.image_postgresql
        image_pull_timeout = "10m"

        ports = ["port_paperless_db"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/paperless-jedd/postgresql:/persistent/postgresql"
        ]

        logging  {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 100
        memory = 250
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

        # "PAPERLESS_URL" = "http://paperless-jedd.obs.int.jeddi.org",
        "PAPERLESS_URL" = "https://ppljedd.obs.int.jeddi.org",

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

        "PAPERLESS_DEBUG" = "false",


        # On smaller systems, or even in the case of Very Large Documents, the consumer may
        # explode, complaining about how it's "unable to extend pixel cache". In such cases,
        # try setting this to a reasonably low value, like 32. The default is to use whatever
        # is necessary to do everything without writing to disk, and units are in megabytes.
        # "PAPERLESS_CONVERT_MEMORY_LIMIT" = 32,

      }

      config {
        image = local.image_paperless
        image_pull_timeout = "10m"

        ports = ["port_paperless"]

        # privileged = true

        volumes = [
          "/opt/sharednfs/paperless-jedd/consume:/persistent/consume",
          "/opt/sharednfs/paperless-jedd/data:/persistent/data",
          "/opt/sharednfs/paperless-jedd/trash:/persistent/trash",
          "/opt/sharednfs/paperless-jedd/media:/persistent/media",
          "/opt/sharednfs/paperless-jedd/log:/persistent/log",
          "/opt/sharednfs/paperless-jedd/BACKUPS/exporter:/persistent/exporter",
        ]

        logging  {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 1600
        memory = 1200
        memory_max = 2500
      }

      service {
        name = "ppljedd"
        port = "port_paperless"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.ppljedd.entrypoints=https,http",
          "traefik.http.routers.ppljedd.rule=Host(`ppljedd.obs.int.jeddi.org`)",
          "traefik.http.routers.ppljedd.tls=false"
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
        image = local.image_postgresql
        image_pull_timeout = "10m"

        command = "/backup-looper.sh"

        volumes = [
          "local/backup-looper.sh:/backup-looper.sh",
          "/opt/sharednfs/paperless-jedd/BACKUPS/db:/persistent/BACKUPS",
        ]

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
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
        image = local.image_tika
        image_pull_timeout = "10m"
        
        ports = ["port_tika"]

        # privileged = true

        volumes = [ ]

        logging  {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 100
        memory = 300
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
        image = local.image_gotenberg
        image_pull_timeout = "10m"
        
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
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 100
        memory = 200
        memory_max = 1024
      }

    } // end-task gotenberg







# TASK - document-exporter = = = = = = = = = = = = = = = = = = = = = = = = =
    task "document-exporter" {
      
      # Custom instance using Nomad CLI image to exec into the paperless
      # container and trigger document_exporter runs on a schedule.

      driver = "docker"

      kill_signal = "SIGTERM"      

      config {
        image = local.image_nomad

        image_pull_timeout = "10m"

        # Run this to avoid the container running `nomad` as the init command
        entrypoint = ["/bin/sh"]

        command = "/backup-looper.sh"
        volumes = [
          "local/backup-looper.sh:/backup-looper.sh",
        ]

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      env = {
        # Point to the local Nomad agent - using host IP since we're in bridge networking
        "NOMAD_ADDR" = "http://${attr.unique.network.ip-address}:4646"
        
        # It's just easier if we have local timezone inside the container.
        "TZ" = "Australia/Sydney"
      }

      resources {
        cpu = 50
        memory = 100
        memory_max = 350
      }

      service {
        name = "document-exporter"
      }

      #  FILE:   backup-looper.sh
      #  This task execs into the running paperless container to trigger document exports.
      #  We use the Nomad CLI to exec into the paperless task within the same allocation,
      #  which means we inherit all of paperless's environment and database connectivity.
      template {
        data = <<EOH
#!/bin/sh

# Use the Nomad-provided allocation ID environment variable
ALLOC_ID="{{ env "NOMAD_ALLOC_ID" }}"

if [ -z "$ALLOC_ID" ]; then
  echo "ERROR: NOMAD_ALLOC_ID not set"
  exit 1
fi

echo "Starting doc-backup loop for allocation: $ALLOC_ID"

while true; do
  # Sleep first, as paperless may not be fully ready on initial startup
  sleep 1h

  HOUR=$(date "+%H")

  # Daily option: run at 2 AM
  if [ "$HOUR" = "02" ]; then
    echo "$(date): Starting document export..."
    
    # Exec into the paperless task in our same allocation and run the exporter
    # The /persistent/exporter volume is mounted in the paperless container
    nomad alloc exec -task paperless "$ALLOC_ID" \
      document_exporter /persistent/exporter --no-archive --no-thumbnail --no-progress-bar --delete

    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
      echo "$(date): Document export completed successfully"
    else
      echo "$(date): Document export failed with exit code: $EXIT_CODE"
    fi
  fi
done

EOH
        destination = "local/backup-looper.sh"
        perms = "755"
      }
    }    #  end-task doc-backup











  }
}

