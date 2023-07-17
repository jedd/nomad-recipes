// jedd lab - loki nomad job -- with persistent storage

// adapted from:  https://atodorov.me/2021/07/09/logging-on-nomad-and-log-aggregation-with-loki/

job "loki" {
  datacenters = ["DG"]
  type        = "service"
  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
  }
  group "loki" {
    count = 1
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "loki_port"  {
        # without traefik
        static = 3100
        # with traefik
        # to = 3100
      }
    }

    volume "loki" {
      type      = "host"
      read_only = false
      source    = "loki"
    }

    task "loki" {
      driver = "docker"
      config {
        image = "grafana/loki:2.4.2"
        args = [
          "-config.file",
          "local/loki.yaml",
          "-log.level",
          "warn",
          "-server.http-listen-port=3100",
        ]
        ports = ["loki_port"]
        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }
      volume_mount {
        volume      = "loki"
        destination = "/loki"
        read_only   = false
      }
      template {
        data = <<EOH

auth_enabled: false

### use the args on the docker call
#server:
#   http_listen_port: 3100

ingester:
  # Jedd 2022-03 - sometimes we see 'permission denied on mkdir /wal' errors, especially with the 2.4.x releases
  #  -- this seems to force the issue and resolves that problem.
  wal:
    enabled: true
    dir: /loki/wal

  lifecycler:
    address: 0.0.0.0
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s

  # Any chunk not receiving new logs in this time will be flushed
  chunk_idle_period: 1h

  # All chunks will be flushed when they hit this age, default is 1h
  max_chunk_age: 1h

  # Loki will attempt to build chunks up to 1.5MB, flushing if chunk_idle_period or max_chunk_age is reached first
  chunk_target_size: 10485760

  # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
  chunk_retain_period: 30s
  max_transfer_retries: 0     # Chunk transfers disabled

schema_config:
  configs:
  - from: 2021-07-01
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h

storage_config:
  boltdb:
    directory: /loki/index
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

compactor:
  working_directory: /tmp/loki/boltdb-shipper-compactor
  shared_store: filesystem

limits_config:
  reject_old_samples: false
  reject_old_samples_max_age: 7d
  ingestion_burst_size_mb: 1500
  ingestion_rate_mb:  160
  # This is default (true) since 2.4.2
  unordered_writes: true

  # 2021-09-09 - set this to 1 weeks.  We were up to 8GB after a few weeks.
  retention_period: 7d

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h

# 2022-03 jedd - to try to reduce the incidence of 'too many outstanding requests' errors
#                on Grafana panels.  The default value is 100, which is WAY too small.
frontend:
  max_outstanding_per_tenant: 4096
query_range:
  split_queries_by_interval: 24h


EOH
        destination = "local/loki.yaml"
      }
      resources {
        cpu    = 512
        memory = 512
      }
      service {
        name = "loki"
        port = "loki_port"
        check {
          name     = "Loki healthcheck"
          port     = "loki_port"
          type     = "http"
          path     = "/ready"
          interval = "20s"
          timeout  = "5s"
          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }

#        tags = [
#          "traefik.enable=true",
#          "traefik.http.routers.loki.rule=Host('loki.int.jeddi.org')",
#          "traefik.http.routers.loki.tls=false",
#          "traefik.http.routers.loki.entrypoints=http,loki",
#        ]

      }
    }
  }
}
