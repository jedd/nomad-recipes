
// Recoll document indexer and query engine.

// Refer: 
// - web UI (this image) -- https://framagit.org/medoc92/recollwebui/
// - recoll itself -- https://www.recoll.org/

// Recoll itself is primarily a desktop application, and the initial build out
// of a web version was mostly abandoned, but subsequently picked up by medoc92.


// Things you need to do:
// -  check your mount points - I use /opt/sharednfs/ as a base and then dirs under
//    that for each application, but you may prefer other mechanisms.
// -  similarly, my documentation is all available at the RO mount under /hub/pub/documentation


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

# Image is generated locally - rather than copied from gh or docker.com - so refer to
# the files in ./assets/recoll-docker-image-build/ directory for guidance on that.


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
variable "nomad_dc" {
  type = string
  default = "PY"
  description = "DC to constrain and run this job - it should be defined in your shell environment"
}

locals {

  image_recoll = "registry.obs.int.jeddi.org/recoll-webui:latest"

  host_constraint = "py-hac-*"

  loki_url = "https://loki-rwb.obs.int.jeddi.org/loki/api/v1/push"
}


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
job "recoll" {
  datacenters = [ var.nomad_dc ]

  type = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = local.host_constraint
  }

  group "recoll" {
    network {
      port "port_recoll" {
        to = 8080
      }
    }

    restart {
      interval = "10m"
      attempts = 20
      delay = "30s"
    }


    // TASK recoll-webui  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
    task "recoll-webui" {

      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        # Recoll uses $HOME/.recoll by default, but we can override with RECOLL_CONFDIR
        # However, the webui doesn't always respect this, so we'll mount directly to /root/.recoll
      }

      config {
        image = local.image_recoll
        image_pull_timeout = "10m"

        # command = "/bin/bash"
        # args = ["-c", "sleep infinity"]

        ports = ["port_recoll"]

        volumes = [
          # Recoll configuration (including our custom recoll.conf)
          "/opt/sharednfs/recoll/config:/root/.recoll",

          "local/recoll.conf:/root/.recoll/recoll.conf",
          
          # Recoll index database
          "/opt/sharednfs/recoll/index:/root/.recoll/xapiandb",
          
          # Document collection (read-only)
          "/hub/pub/documentation:/documents:ro",

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
        cpu = 400
        memory = 512
        memory_max = 2048
      }

      service {
        name = "recoll"
        port = "port_recoll"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.recoll.entrypoints=https,http",
          "traefik.http.routers.recoll.rule=Host(`recoll.obs.int.jeddi.org`)",
          "traefik.http.routers.recoll.tls=false"
        ]      

      }

      # Note: recoll.conf will be created by the template below on first run

      template {
        data = file("assets/recoll.conf")
        destination = "local/recoll.conf"
      }

    } // end-task recoll-webui


    // TASK recoll-indexer  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
    task "recoll-indexer" {
      
      driver = "docker"

      kill_signal = "SIGTERM"      

      config {
        image = local.image_recoll
        image_pull_timeout = "10m"

        command = "/bin/bash"
        args = ["/indexer-looper.sh"]

        volumes = [
          "local/indexer-looper.sh:/indexer-looper.sh",

          "/opt/sharednfs/recoll/config:/root/.recoll",
          "local/recoll.conf:/root/.recoll/recoll.conf",

          "/opt/sharednfs/recoll/index:/root/.recoll/xapiandb",

          "/hub/pub/documentation:/documents:ro",
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
        "TZ" = "Australia/Sydney"
      }

      resources {
        cpu = 1200
        memory = 1536
        memory_max = 4096
      }

      service {
        name = "recoll-indexer"
      }

      template {
        data = file("assets/recoll.conf")
        destination = "local/recoll.conf"
      }

      template {
        data = <<EOH
#! /usr/bin/env bash

# Recoll indexer daemon - runs daily reindexing at scheduled time
#
# Sleeps regularly, wakes to check if we're in the right window (3-4am),
# and if so runs recollindex to update the search index.

# Log helper function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Recoll indexer daemon starting"
log "Waiting 30 seconds for volumes to be ready..."
sleep 30

# Check if recoll.conf exists, if not wait for webui task to create it
while [ ! -f /root/.recoll/recoll.conf ]; do
  log "Waiting for recoll.conf to be created..."
  sleep 10
done

log "Configuration file found, indexer ready"

# On first run, check if we should do an initial index
if [ ! -d /root/.recoll/xapiandb ] || [ -z "$(ls -A /root/.recoll/xapiandb 2>/dev/null)" ]; then
  log "No existing index found - you may want to run initial indexing manually:"
  log "  nomad alloc exec -task recoll-indexer <ALLOC_ID> recollindex"
  log "Or wait for the scheduled run at 3am"
fi

while [ 1 ]
do
  # Sleep first - on startup the volumes may not be fully ready
  sleep 1h

  HOUR=$(date "+%H")

  # Run indexing between 3am-4am
  if [ ${HOUR} -eq 03 ]
  then
    log "Starting recollindex run"
    log "Document directory: /documents"
    log "Index directory: /root/.recoll/xapiandb"
    
    # Show some stats before indexing
    log "Disk usage before indexing:"
    du -sh /root/.recoll/xapiandb 2>/dev/null || log "  (no index yet)"
    
    # Run the indexer
    # For initial run (first time), use -z to purge and rebuild:
    #   recollindex -z
    # For daily incremental updates (recommended after initial index):
    #   recollindex
    
    # We'll do incremental by default (faster)
    recollindex
    
    INDEX_EXIT_CODE=$?
    
    if [ ${INDEX_EXIT_CODE} -eq 0 ]; then
      log "Recollindex completed successfully"
    else
      log "ERROR: Recollindex failed with exit code ${INDEX_EXIT_CODE}"
    fi
    
    # Show index statistics
    log "Index statistics:"
    recollindex -S
    
    log "Disk usage after indexing:"
    du -sh /root/.recoll/xapiandb
    
    log "Indexing complete, returning to sleep"
  fi
done

EOH
        destination = "local/indexer-looper.sh"
        perms = "755"
      }
    } // end-task recoll-indexer

  } // end-group recoll
}

