
# Jedd lab - registry - a combination of 'distribution' and 'registry ui'

# hac refers to 'high availability cluster' (somewhat misnamed as my potential
# Nomad VMs are all running on the same physical server).

# Documentation:   https://distribution.github.io/distribution/
# Configuration:   https://hub.docker.com/r/joxit/docker-registry-ui

# = = = = = = = = = = = = = = = = = = = 
# For the DISTIBUTION (actual registry)

# Refer:  https://github.com/distribution/distribution

# When I initially built this, I had no internal network SSL, but have since
# got letsencrypt working, which reduces some of the previous sharp edges.
#
# For example, without SSL, you need to set 'insecure-registries' in your
# docker configuratio.

# Troubleshooting:
# To validate a) contents, and b) persistent storage, you can query the
# contents of your registry with something like:
#  curl -X GET https://registry.obs.int.jeddi.org/v2/_catalog
#
# To see tags for a repo:
#  curl -X GET https://registry.obs.int.jeddi.org/v2/traefik/tags/list

# To populate the registry you can do the docker pull, docker tag, docker push
# process, or use the package 'skopeo' which is a bit simpler, eg:
# Note, without SSL, you'll need the skopeo flag:  --dest-tls-verify=false 
#
#   skopeo copy                                                         \
#          docker://registry.hub.docker.com/library/traefik:v3.1.5      \
#          docker://registry.obs.int.jeddi.org/traefik:v3.1.5

# = = = = = = = = = = =
# For the REGISTRY UI:

# Refer:
#   https://joxit.dev/docker-registry-ui/

# A web GUI front end to the 'distribution' nomad job, also tied to
# https://registry-ui.obs.int.jeddi.org

# Delete (from UI) requires distribution config has
#     storage / delete / enabled = true
# .. but will still need purging.  (Refer below.)



# Variables  = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
// As of 2025 I'm now configuring my jobs to run at either of my locations,
// and using environment variable to identify / force this when running
// jobs via bash using the nomad CLI.
variable "nomad_dc" {
  type = string
  default = ""
  description = "DC to constrain and run this job - it should be defined in your shell environment"
}

locals {
  # For basically ALL OTHER containers on my network, I refer to registry.obs.int.jeddi.org,
  # but obviously bootstrapping _that_ requires these come from docker hub.
  image_distribution = "registry:2.8.3"
  image_registry_ui = "joxit/docker-registry-ui:main"

  host_constraint = var.nomad_dc == "DG" ? "dg-hac-*" : "py-hac-*"

  loki_url = "https://loki.obs.int.jeddi.org/loki/api/v1/push"
}


# Job  = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
job "registry"  {
  datacenters = [ var.nomad_dc ]

  type = "service"

  update {
    healthy_deadline = "1m"
    progress_deadline = "2m"
  }

  group "registry" {
    network {
      port "port_distribution" {
        to = 5000
      }
      port "port_registry_ui" {
        to = 5001
      }
      port "port_distribution_metrics" {
        to = 5002
      }
    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

    constraint {
      attribute = "${attr.unique.hostname}"
      operator = "regexp"
      value = local.host_constraint
    }

    # TASK  registry-ui  = = = = = = = = = = = = = = = = = = = = = = = =
    task "registry-ui" {
      driver = "docker"

      # Politeness
      kill_timeout = "10s"
      kill_signal = "SIGTERM"

      env = {
        # It's just easier if we have local timezone inside the container.
        "TZ" = "Australia/Sydney",

        # Registry-UI specific features
        "CATALOG_ELEMENTS_LIMIT" = "1000"
        "CATALOG_MAX_BRANCHES" = "1"
        "CATALOG_MIN_BRANCHES" = "1"
        "DELETE_IMAGES" = "true"

        # "NGINX_LISTEN_PORT" = "5001"
        "NGINX_LISTEN_PORT" = "${NOMAD_HOST_PORT_port_registry_ui}"

        "NGINX_PROXY_PASS_URL" = "http://localhost:${NOMAD_HOST_PORT_port_distribution}"

        # "REGISTRY_LOG_LEVEL" = "info"
        "REGISTRY_LOG_LEVEL" = "warn"

        # By default, the UI will check on every requests if your registry is 
        # secured or not (you will see 401 responses in your console). Set to 
        # true if your registry uses Basic Authentication.
        "REGISTRY_SECURED" = "false"

        "REGISTRY_TITLE" = "Docker distribution registry for obs.int.jeddi.org"
        # DO NOT SET REGISTRY_URL - but instead just set NGINX_PROXY_PASS_URL (above) - and
        # DON'T SET THAT to the public / tls / https endpoint available via traefik, but rather
        # just http: to localhost and the nomad mapped port for distribution registry (not ui).
        # "REGISTRY_URL" = "http://registry.obs.int.jeddi.org"

        "SHOW_CATALOG_NB_TAGS" = "true"
        "SHOW_CONTENT_DIGEST" = "true"
        "SINGLE_REGISTRY" = "true"
        "TAGLIST_PAGE_SIZE" = "100"
        "THEME" = "dark"
      }

      config {
        image = local.image_registry_ui

        ports = ["port_registry_ui"]

        network_mode = "host"

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      resources {
        cpu = 200
        memory = 200
        memory_max = 300
      }

      service {
        name = "registry-ui"
        port = "port_registry_ui"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.registry-ui.rule=Host(`registry-ui.obs.int.jeddi.org`)",
          "traefik.http.routers.registry-ui.entrypoints=https",
          "traefik.http.routers.registry-ui.tls=true",
        ]
      }

    } // end-task registry ui


    # TASK  distribution  = = = = = = = = = = = = = = = = = = = = = = =
    task "distribution" {
      driver = "docker"

      # Politeness
      kill_timeout = "10s"
      kill_signal = "SIGTERM"

      env = {
        # It's just easier if we have local timezone inside the container.
        "TZ" = "Australia/Sydney",

        # Experimenting - these two are a) non-obvious, and/or b) not needed.
        #"REGISTRY_HTTP_HEADERS_Access-Control-Allow-Credentials" =  "[true]",
        #"REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin" = "[ https://registry-ui.obs.int.jeddi.org ]",
        "REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin" = "['*']",
      }

      config {
        image = local.image_distribution

        ports = ["port_distribution"]

        volumes = [ 
          # Persistent storage for docker images
          "/opt/sharednfs/distribution/var-lib-registry:/var/lib/registry",

					# Taken from vanilla instance and modified (refer template below)
          "local/etc-docker-registry-config.yml:/etc/docker/registry/config.yml",

					# Modify entrypoint.sh to introduce a background GC process
          "local/new-entrypoint.sh:/entrypoint.sh",
          "local/garbage-collector.sh:/garbage-collector.sh"
        ]

        network_mode = "host"

        logging {
          type = "loki"
          config {
            loki-url = local.loki_url
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

      }

      resources {
        cpu = 100
        memory = 400
        memory_max = 800
      }

      template {
        data = <<EOH
#!/bin/sh
# This file injected by the Nomad job.

# Change #1 to entrypoint - force tzdata so we can respect TZ env variable
# (This works because this is an alpine image - and is needed because Alpine
# does NOT ship with /usr/share/zoneinfo/ hierarchy, so it ignores the TZ.)
apk add --no-cache tzdata 
cp /usr/share/zoneinfo/${TZ} /etc/localtime
export TZ=${TZ}

set -e

# Change #2 to entrypoint - launch the injected garbage collector script to
# run every 24h.
exec /garbage-collector.sh &

case "$1" in
    *.yaml|*.yml) set -- registry serve "$@" ;;
        serve|garbage-collect|help|-*) set -- registry "$@" ;;
        esac

        exec "$@"

EOH
        destination = "local/new-entrypoint.sh"
        perms = "0755"
      }

      template {
        data = <<EOH
#!/bin/sh
# This file injected by the Nomad job
# It spawns a separate process within the container to periodically run the 
# garbage collector, to purge files deleted via the docker registry UI .

export TZ=${TZ}

log_gc() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [GC] $1"
}

while true; do
  log_gc "Starting garbage collection for registry"
  registry garbage-collect /etc/docker/registry/config.yml
  log_gc "Finished garbage collection for registry"
  log_gc "Sleeping for 24 hours"
  sleep 24h
done

EOH
        destination = "local/garbage-collector.sh"
        perms = "0755"
      }


      template {
        data = <<EOH
# Configuration managed via nomad job
# Refer:  https://distribution.github.io/distribution/about/configuration/

version: 0.1
log:
  # level == debug, 
  level: warn
  fields:
    service: registry

storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true

http:
  addr: 0.0.0.0:{{ env "NOMAD_HOST_PORT_port_distribution" }}

  # Externally reachable address for the registry - used to create generated URLs
  host: https://registry.obs.int.jeddi.org/

  headers:
    X-Content-Type-Options: [nosniff]

    # Access-Control-Allow-Origin: ['https://registry-ui.obs.int.jeddi.org']
    Access-Control-Allow-Origin: ['*']

  debug:
    addr: 0.0.0.0:{{ env "NOMAD_HOST_PORT_port_distribution_metrics" }}
    prometheus:
      enabled: true
      path: /metrics

health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3

EOH
        destination = "local/etc-docker-registry-config.yml"
      }

      service {
        name = "registry"
        port = "port_distribution"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.registry.rule=Host(`registry.obs.int.jeddi.org`)",
          "traefik.http.routers.registry.entrypoints=https,http",
          "traefik.http.routers.registry.tls=false",
        ]
      }

    }  // end-task distribution

  }
}

