
// immich - web based multi-user photo management

// 2026-03-14 - initial attempt

// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

# My interpretation of the installation instructions (official) from:
#     https://docs.immich.app/install/docker-compose

// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

# Prior art - Daniel Berteaud's at:
#             https://git.lapiole.org/nomad/immich/src/branch/master/example/immich.nomad.hcl
#
#             Matthias Schoger's at:
#             https://github.com/matthiasschoger/hashilab-apps/blob/master/immich/compose.hcl


# Architecture notes:
#  - I already have TLS (via Traefik), Consul, and a RR DNS so I don't need any 
#    sidecar complexity.
#
#  - Will have all tasks on one box, as my lab is (primarily) one machine, so I don't
#    need count > 1 for the ML tasks. This also simplifies access to redis interface.
#
#  - Related, I can use the NOMAD_IP connections to talk to postgresql and redis (no
#    need to bounce through DNS / Traefik).
#
#  - Would like to have postgres sitting on an NFS share so I have some mobility with
#    the job, but appreciate the `pgvecto.rs` stuff is chatty, so I'll start with 
#    `/opt/localstore` as the store, which means constraining to one VM, at least for
#    the initial scanning / loading of the photo repository.
#
#  - Augmenting that - I'll constrain to `py-hac-04` AND set up a 44GB volume in
#    proxmox that is locked to the SSD in that box - called `local-lvm` device 
#    (`/dev/sda`) and presents at `/opt/localstore-ssd` on the py-hac-04 VM.
#
#  - Matthias uses the immich postgres which bundles the VectorChord extension, and
#    I assume Daniel's external postgresql system already has that.  I'll use the
#    immich postgres image also.
#
#  - For backups & archives, I'll use a similar approach to my paperless - a call
#    into the immich container to hit `immich-cli` and a simple postgres/bash task
#    to do the pg_dump.  (Though this complexity may not be needed, as the system
#    generates a nightly postgresql dump out to the file system anyway, and retains
#    (default) 14 of those. I can take those off-box and keep adjacent the other
#    copies of the 500GB of photos.
#
#  - I want Prometheus metrics - immich-exporter gives me some stuff beyond what
#    the generic prometheus /metrics endpoints (ml & api) provide.
#
#  - Matthias specifies the PRELOAD settings, and while he's using defaults, this
#    does force the model to  stay in memory from startup (rather than load on
#    first use *and* eject from (V)RAM after some time-out period of idle).  I'll
#    use the PRELOAD to force it to never evict.
#
#  - Secrets will live in Consul K/V. (I've got Vault, but it's more experimental.)
#
#  - The CUDA variant of the model is a drop-in replacement for ML container/task, 
#    but does require nvidia / cuda drivers at the OS layer *and* the container 
#    toolkit packages for Debian:
#    https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html


#  - I believe that:
#    a)  Immich uses redis as a job queue & cache, not as a source of truth, so I can
#        treat those data as ephemeral.
#
#    b)  there's an unknown with the best way of handling the machine learning model cache,
#        which Matthias uses ephemeral disk for, and hopes the migration (by Nomad) covers
#        most cases, and it's rebuilt (annoying but not catastrophic) in the worst case.


# Gotchas and caveats
#  - Iterating through a development cycle has some sharp edges, notably the postgresql DB
#    needs to align with the reality of what's in the `/library` data structure, specifically
#    immich tries to write (and read!) sentinel files, eg /library/backups/.immich - BUT
#    if you stop the job, destroy the library contents or point to a new directory, then
#    at starup the task 'immich-server' will fail, as it will try to read from those dirs.
#    The easiest workaround is to delete the postgresql contents and have the whole thing
#    re-create. Bodgy workarounds of creating the dir-structure and touching `.immich` files
#    at each path might work. I gave up on it.


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
variable "nomad_dc" {
  type = string
  default = "PY"
  description = "DC to constrain and run this job - it should be defined in your shell environment"
}

// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
locals {
  # --------------------------------------------------------------------------
  # 2026-03-15 - current release is v2.5.6, but docker-compose.yml is the
  #        canonical source for contemporary versions that will inter-op well.
  # --------------------------------------------------------------------------

  # Refer: https://github.com/immich-app/immich/releases
  # skopeo copy 
  #        docker://ghcr.io/immich-app/immich-server:v2.5.6 
  #        docker://registry.obs.int.jeddi.org/immich-server:v2.5.6
  image_immich = "registry.obs.int.jeddi.org/immich-server:v2.5.6"

  # CPU variant ( 435MB )
  # skopeo copy 
  #        docker://ghcr.io/immich-app/immich-machine-learning:v2.5.6 
  #        docker://registry.obs.int.jeddi.org/immich-machine-learning:v2.5.6
  #
  # CUDA variant ( 2.5GB )
  # skopeo copy 
  #        docker://ghcr.io/immich-app/immich-machine-learning:v2.5.6-cuda 
  #        docker://registry.obs.int.jeddi.org/immich-machine-learning:v2.5.6-cuda

  # If enabling the CUDA variant - update the two other `NVIDIA CUDA` entries in this job spec. 
  image_immich_machine_learning = "registry.obs.int.jeddi.org/immich-machine-learning:v2.5.6"
  # image_immich_machine_learning = "registry.obs.int.jeddi.org/immich-machine-learning:v2.5.6-cuda"

  # skopeo copy 
  #        docker://ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0  
  #        docker://registry.obs.int.jeddi.org/postgres:14-vectorchord0.4.3-pgvectors0.2.0
  image_postgresql = "registry.obs.int.jeddi.org/postgres:14-vectorchord0.4.3-pgvectors0.2.0"

  # skopeo copy 
  #        docker://docker.io/library/redis:7 
  #        docker://registry.obs.int.jeddi.org/redis:7
  # image_redis = "docker.io/library/redis:7"
  image_redis = "registry.obs.int.jeddi.org/redis:7"

  # Locking in to py-hac-04 while we get the postgres/vector stuff working
  # host_constraint = "py-hac-*"
  host_constraint = "py-hac-04"

  # loki_url = "https://loki.obs.int.jeddi.org/loki/api/v1/push"
  loki_url = "https://loki-rwb.obs.int.jeddi.org/loki/api/v1/push"

  # Common environment variables
  #puid = "1000"
  #pgid = "1000"
  timezone = "Australia/Sydney"
}


// = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
job "immich" {
  datacenters = [ var.nomad_dc ]

  type = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    operator = "regexp"
    value = local.host_constraint
  }

  group "immich" {
    network {
      port "port_immich" {
        to = 2283
      }
      # API metrics - enabled by env variable IMMICH_TELEMETRY_INCLUDE
      port "port_immich_metrics_api" {
        to = 8081
      }
      # Microservices metrics - enabled by env variable IMMICH_TELEMETRY_INCLUDE
      port "port_immich_metrics_ms" {
        to = 8082
      }

      port "port_immich_machine_learning" {
        to = 3003
      }

      port "port_redis" {
        to = 6379
      }

      port "port_db" {
        to = 5432
      }

    }

    restart {
      interval = "10m"
      attempts = 20
      delay = "30s"
    }


    // TASK immich-server  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
    task "immich-server" {
      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        # immich uses an env file we load (template) below.
        "TZ" = local.timezone

        "REDIS_HOSTNAME"      = "${NOMAD_IP_port_redis}"
        "REDIS_PORT"          = "${NOMAD_HOST_PORT_port_redis}"

        # This is the same setting - annoyingly with a different name - to the immich.env file's
        # UPLOAD_LOCATION entry, so they need to be EITHER one active, or both set the same (or sane).
        "IMMICH_MEDIA_LOCATION" = "/library"

        "DB_HOSTNAME"         = "${NOMAD_IP_port_db}"
        "DB_PORT"             = "${NOMAD_HOST_PORT_port_db}"
        "IMMICH_MACHINE_LEARNING_URL" = "http://${NOMAD_ADDR_port_immich_machine_learning}"

        # Metrics exposure - you can de-tune what's exposed, but I'd rather select / drop on the 
        # Prometheus side. This only works for 'immich-server' container, and exposes metrics for
        # API on tcp/8081, and Microservices on tcp/8082.
        "IMMICH_TELEMETRY_INCLUDE" = "all"

        # Log level can be [verbose, debug, log, warn, error]
        "IMMICH_LOG_LEVEL" = "warn"
      }

      config {
        image = local.image_immich
        image_pull_timeout = "10m"

        # For debugging
        # entrypoint = ["/bin/sh", "-c", "sleep infinity"]

        ports = [ "port_immich",
                  "port_immich_metrics_api",
                  "port_immich_metrics_ms",
        ]

        volumes = [
          # I'll mount the library here at some point - but they don't seem to have
          # a separate upload dir from a primary library collection, so I'm probably
          # going to have to have the nfs mount to the garden / photos - one level down,
          # and allow modification of parent, or a peer directory.

          # "/opt/py-garden-01/garden/pictures:./library",
          "/opt/localstore/immich/library:/library",
          "/opt/localstore/immich/external-library:/external-library:ro",
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
        cpu = 1000
        memory = 6144
        memory_max = 8192
      }

      service {
        name = "immich"
        port = "port_immich"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.immich.entrypoints=https",
          "traefik.http.routers.immich.rule=Host(`immich.obs.int.jeddi.org`)",
          "traefik.http.routers.immich.tls=true"
        ]
      }

      service {
        name = "immich-metrics-api"
        port = "port_immich_metrics_api"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.immich-metrics-api.entrypoints=https",
          "traefik.http.routers.immich-metrics-api.rule=Host(`immich-metrics-api.obs.int.jeddi.org`)",
          "traefik.http.routers.immich-metrics-api.tls=true"
        ]
      }

      service {
        name = "immich-metrics-ms"
        port = "port_immich_metrics_ms"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.immich-metrics-ms.entrypoints=https",
          "traefik.http.routers.immich-metrics-ms.rule=Host(`immich-metrics-ms.obs.int.jeddi.org`)",
          "traefik.http.routers.immich-metrics-ms.tls=true"
        ]
      }

      template {
        data = file("assets/immich.env")
        destination = "immich.env"
        env = true
      }

    } // end-task immich


    // TASK immich-machine-learning  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
    task "immich-machine-learning" {
      driver = "docker"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        # immich uses an env file we load (template) below.
        "TZ" = local.timezone

        # NVIDIA CUDA - only for nvidia/cuda ML systems
        #"NVIDIA_VISIBLE_DEVICES" = "all"

        # Force pre-loading of these default models:
        # Default - okay, but not great
        # "MACHINE_LEARNING_PRELOAD__CLIP" = "ViT-B-16-SigLIP-256__webli"

        # More modern, about 4GB footprint - so fine on an 8GB GPU with CUDA
        "MACHINE_LEARNING_PRELOAD__CLIP" = "ViT-SO400M-16-SigLIP2-384__webli"

        "MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION" = "buffalo_l"

        # This is the default, and the host has 6 cores at time of development, so
        # default is fine.
        "MACHINE_LEARNING_REQUEST_THREADS" = "4"

        # Log level can be [verbose, debug, log, warn, error]
        "IMMICH_LOG_LEVEL" = "warn"
      }

      config {
        image = local.image_immich_machine_learning
        image_pull_timeout = "10m"

        # NVIDIA CUDA - this needs to be enabled ONLY on nvidia/cuda systems
        # runtime = "nvidia"

        ports = ["port_immich_machine_learning"]

        volumes = [
          # This cache should be persistent, but does not need SSD speeds,
          # and it's not clear what size it may grow to.
          "/opt/localstore/immich/model-cache:/cache"
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
        cpu = 1000
        memory = 6144
        memory_max = 10240
      }

      service {
        name = "immich-ml"
        port = "port_immich_machine_learning"
      }

      template {
        data = file("assets/immich.env")
        destination = "immich.env"
        env = true
      }

    } // end-task immich-machine-learning


    # TASK - redis = = = = = = = = = = = = = = = = = = = = = = = = =
    task "redis" {
      driver = "docker"

      # This service is accessible at: 
      #    "redis://${NOMAD_ADDR_port_redis}"

      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        "TZ" = local.timezone
      }

      config {
        image = local.image_redis
        image_pull_timeout = "10m"

        args = [
          # "/etc/redis.conf",
          # Not using persistent disk storage
          # "--save",  "60 1",
          "--save",  "",
          "--loglevel",  "warning",
        ]

        ports = ["port_redis"]

        volumes = [
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
        name = "redis"
        port = "port_redis"
      }

#      template {
#        data = <<EOH
#DIR /persistent/redis-data
#
#EOH
#        destination = "local/redis.conf"
#      }

    }  // end-task redis



    # TASK - db = = = = = = = = = = = = = = = = = = = = = = = = =
    task "db" {
      # The PostgreSQL database
      driver = "docker"

      # Try to give PostgreSQL a little while to terminate sanely.
      kill_timeout = "30s"
      kill_signal = "SIGTERM"

      env = {
        "TZ" = local.timezone

        # This is done via the env file
        "PGDATA" = "/persistent/postgresql/data",

        # These are pulled in from the 'env=true' template below.
        #"POSTGRES_PASSWORD" = ...
        #"POSTGRES_USER" = ...
        #"POSTGRES_DB" = ...

        "POSTGRES_INITDB_ARGS" = "--data-checksums",

        # DB_STORAGE_TYPE can be ["HDD", "SSD"] and dictates optimisations
        # for concurrent vs sequential I/O on storage.
        "DB_STORAGE_TYPE" = "SSD",
      }

      config {
        image = local.image_postgresql

        # This is per docker-compose's reference - 128MB shared memory.
        shm_size = 134217728

        ports = ["port_db"]

        volumes = [
          # This is obviously only available on py-hac-04.
          # Be sure to change the assets/immich.env file.
          # "/opt/localstore-ssd/immich/postgresql/data:/var/lib/postgresql/data"
          "/opt/localstore-ssd/immich/postgresql:/persistent/postgresql"
        ]

        logging  {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      # Need to do this ugly hack - pull Consul k/v into Nomad space
      template {
        data = <<-EOH
POSTGRES_PASSWORD={{ key "immich/postgres-password" }}
POSTGRES_USER={{ key "immich/postgres-user" }}
POSTGRES_DB={{ key "immich/postgres-db" }}
EOH
        destination = "secrets/db-credentials.env"
        env         = true
      }

      resources {
        cpu = 1000
        memory = 2048
        memory_max = 4096
      }

      service {
        name = "immich-db"
        port = "port_db"
      }
    }  // end-task db

  }
}

