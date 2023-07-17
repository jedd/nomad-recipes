
// cortex (single instance version) for jedd's nomad lab (DG)

variables {
  consul_hostname = "dg-pan-01.int.jeddi.org:8500"
}

job "cortex" {
  datacenters = ["DG"]
  type = "service"

  group "cortex" {
    network {
      port "port_http" {
        static = 9009
      }
      port "port_grpc" {
        static = 9095
      }
    }

    volume "vol_cortex"  {
      type = "host"
      source = "vol_cortex"
      read_only = false
    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

    # I previously had a multi-node cluster, and needed to constrain to the server with the storage.
    constraint {
      attribute = "${attr.unique.hostname}"
      value = "dg-pan-01"
    }

    task "cortex" {
      driver = "docker"

      volume_mount {
        volume = "vol_cortex"
        destination = "/mnt/cortex"
        read_only = false
      }

      config {
        image = "https://quay.io/cortexproject/cortex:v1.9.0"
        dns_servers = ["192.168.27.123"]
        ports = ["port_http", "port_grpc"]
        volumes = []
        args = [
          "-config.file=/local/cortex.yml",
          "-config.expand-env",
          "-ring.store=consul",
          "-consul.hostname=dg-pan-01.int.jeddi.org:8500",
          "-log.level=warn",
          "server.http_listen-address=192.168.27.123",
          "server.grpc_listen-address=192.168.27.123"
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
        cpu = 500
        memory = 4096
      }

      service {
        name = "cortex-ruler"
        port = "port_http"
      }

      service {
        name = "openmetrics"
        port = "port_http"
      }

      service {
        name = "cortex-querier"
        port = "port_http"
      }

      service {
        name = "cortex-store-gateway"
        port = "port_http"
      }

      service {
        name = "cortex"
        port = "port_http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.cortex.rule=Host(`cortex.int.jeddi.org`)",
          "traefik.http.routers.cortex.tls=false",
        ]

        check {
          type = "http"
          port = "port_http"
          path = "/services"
          interval = "60s"
          timeout = "10s"
        }

      }

      service {
        name = "cortex-query-frontend"
        port = "port_http"
        tags = ["traefik.enable=true"]

#        check {
#          type = "http"
#          port = "port_http"
#          path = "/services"
#          interval = "30s"
#          timeout = "5s"
#        }
      }

      template {
        data = <<EOH

# Configuration for running Cortex in single-process mode.
# This should not be used in production.  It is only for getting started
# and development.

# Disable the requirement that every request to Cortex has a
# X-Scope-OrgID header. `fake` will be substituted in instead.
auth_enabled: false

server:
  http_listen_port: 9009

  # Configure the server to allow messages up to 100MB.
  grpc_server_max_recv_msg_size: 104857600
  grpc_server_max_send_msg_size: 104857600
  grpc_server_max_concurrent_streams: 1000

  # 2021-10-15 jedd - add this, as INFO is huge.  
  # options are [debug, info, warn, error]
  # also, CLI flag: -log.level
  log_level: "warn"

distributor:
  shard_by_all_labels: true
  pool:
    health_check_ingesters: true

ingester_client:
  grpc_client_config:
    # Configure the client to allow messages up to 100MB.
    max_recv_msg_size: 104857600
    max_send_msg_size: 104857600
    grpc_compression: gzip

ingester:
  lifecycler:
    # The address to advertise for this ingester.  Will be autodiscovered by
    # looking up address on eth0 or en0; can be specified if this fails.
    # address: 127.0.0.1

    # We want to start immediately and flush on shutdown.
    join_after: 0
    min_ready_duration: 0s
    final_sleep: 0s
    num_tokens: 512

    # Use an in memory ring store, so we don't need to launch a Consul.
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1

storage:
  engine: blocks

blocks_storage:
  backend: filesystem
  filesystem:
    dir: /mnt/cortex/blocks
  tsdb:
    dir: /mnt/cortex/ingester/tsdb
    # Default is 2h hours, but this is frustrating in a lab environment with regular restarts
    # Alternative to dropping this down to 5m (say) is to persist the TSDB data - as above,
    # this is now moved to /mnt/cortex/... (persistent).
    block_ranges_period: ["1h0m0s"]

#  bucket_store:
#    sync_dir: /tmp/cortex/tsdb-sync


compactor:
  # data_dir: /tmp/cortex/compactor
  data_dir: /alloc/cortex/compactor
  sharding_ring:
    kvstore:
      store: inmemory

frontend_worker:
  match_max_concurrent: true

ruler:
  enable_api: true
  enable_sharding: false

ruler_storage:
  backend: filesystem
  # This is a bit confusing, but ruler has one storage for rule evaluation and one for storing rules. 
  # This one is the evaluation cache.
  filesystem:
    dir: /alloc/cortex/ruler
  local:
    directory: /local/cortex/rules


EOH
        destination = "local/cortex.yml"
      }
    }
  }
}
