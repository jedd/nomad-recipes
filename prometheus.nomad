
// jedd lab - prometheus - with persistent storage

job "prometheus" {
  type = "service"
  datacenters = ["DG"]

  group "prometheus" {
    
    # For long-term-storage (LTS) of time-series TSDB
    volume "promvol"  {
      type = "host"
      source = "promvol"
      read_only = false
      }

# For external configuration (prometheus-configuation, including alert-manager rules)
#    volume "promconfvol"  {
#      type = "host"
#      source = "promconfvol"
#      read_only = false
#      }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

    # We really only want this running on the main server
    constraint {
      attribute = "${attr.unique.hostname}"
      value = "dg-pan-01"
    }

    network {
      port "prometheus" {
        static = 9090
      }
  	}

    task "prometheus" {
      driver = "docker"

      volume_mount {
        volume = "promvol"
        destination = "/prometheus"
        read_only = false
      }

#      volume_mount {
#        volume = "promconfvol"
#        destination = "/prometheus-configuration"
#        read_only = false
#        }

      config {
        image = "https://docker.io/prom/prometheus:v2.28.1"
        args = [
          "--storage.tsdb.retention.time=1y" ,
          "--config.file=/etc/prometheus/prometheus.yml"
        ]
        dns_servers = ["192.168.27.123"]

#        mounts = [
#          {
#            type = "volume"
#            target = "/prometheus-configuration"
#            source = "promconfvol"
#          }
#        ]

        volumes = [ 
          "local/prometheus.yaml:/etc/prometheus/prometheus.yml",
          "local/prometheus-configuration/prometheus/rules:/etc/prometheus/rules.d"
        ]

        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }

        network_mode = "host"
      }

      service {
        name = "prometheus-http"
        port = "prometheus"

       check {
         type = "http"
         port = "prometheus"
         path = "/-/healthy"
         interval = "20s"
         timeout = "10s"
       }
      }

      artifact {

      # I use gitolite as my personal git repository server - it works reliably, but is
      # not a commonly supported back-end.
      #
      # The following configuration requires gitolite-admin to add a public key to the
      # prometheus-configuration repository, which is an entirely optional entity, and
      # depends on how you want to manage prometheus.  It's possible to do primarily
      # service discovery (SD) via Consul, but I kept on finding edge cases, and also
      # quick experiments were easier with an old-fashioned configuration file.

      source = "git::ssh://gitolite@git.mygitoliteserver/prometheus-configuration"
      destination = "local/prometheus-configuration"
      options {
        sshkey = " -- redacted SSH public key to gitolite repository -- "
        }
      }

      template {
        data = <<EOH

global:
  external_labels:
    nomad_job_name: {{ env "NOMAD_JOB_NAME" }}
    nomad_task_name: {{ env "NOMAD_TASK_NAME" }}
    nomad_alloc_id: {{ env "NOMAD_ALLOC_ID" }}
  scrape_interval: 1m

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'telegraf-static'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:9273', 'jarre.int.jeddi.org:9273',
                 'dg-hassio-01.int.jeddi.org:9273', 'freya.int.jeddi.org:9273']

  - job_name: 'esp_iot_weather_station-shed'
    static_configs:
      - targets: ['esp-shed:80']
        labels:
          name: esp-shed
          location: shed
    metrics_path: /metrics

  - job_name: 'esp_iot_weather_station-cabin'
    static_configs:
      - targets: ['esp-cabin:80']
        labels:
          name: esp-cabin
          location: cabin
    metrics_path: /metrics

  - job_name: 'windows-exporter-static'
    static_configs:
      - targets: ['shpongle.int.jeddi.org:9182']

  - job_name: 'nomad_metrics'
    static_configs:
      # - targets: ['dg-pan-01.int.jeddi.org:4646', 'jarre.int.jeddi.org:4646']
      - targets: ['dg-pan-01.int.jeddi.org:4646']
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']


  - job_name: 'consul_metrics'
    static_configs:
      # - targets: ['dg-pan-01.int.jeddi.org:8500', 'jarre.int.jeddi.org:8500']
      - targets: ['dg-pan-01.int.jeddi.org:8500']
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']

  - job_name: 'promtail_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:9080',
                  'jarre.int.jeddi.org:9080',
                  'dg-hassio-01.int.jeddi.org:9080'
                 ]
    metrics_path: /metrics

  - job_name: 'loki_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:3100']
    metrics_path: /metrics

  - job_name: 'traefik_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:8081',
                  'jarre.int.jeddi.org:8081']
    metrics_path: /metrics

  - job_name: 'oracle_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:9161']
    metrics_path: /metrics

  - job_name: 'grafana_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:3000']
    metrics_path: /metrics

  - job_name: 'nodered_metrics'
    static_configs:
      - targets: ['nodered.int.jeddi.org:8080']
    metrics_path: /metrics

  - job_name: 'starlink_metrics'
    static_configs:
      - targets: ['dg-pan-01.int.jeddi.org:9817']
    metrics_path: /metrics


#  - job_name: 'ping_member_servers_static'
#    # @TODO in production we're happy with very low poll rate
#    # scrape_interval: 10m
#    scrape_interval: 1m
#    static_configs:
#      # use cameras, which have no metrics capability
#      - targets: ['192.168.27.220', '192.168.27.221', '192.168.27.227']
#    metrics_path: /probe
#    params:
#      module: [icmp]
#    relabel_configs:
#      - source_labels: [__address__]
#        target_label: __param_target
#      - source_labels: [__param_target]
#        target_label: instance
#      - target_label: __address__
#        # blackbox binds to public ethernet, not loopback
#        replacement: 192.168.27.123:9115

#   - job_name: 'ping_member_servers_sd'
# #   scrape_interval: 1m
#     metrics_path: /probe
#     params:
#       module: ["icmp"]
#     consul_sd_configs:
#       - server: 'dg-pan-01.int.jeddi.org:8500'
#         datacenter: 'dg'
#         services: ['pingtarget']
#     relabel_configs:
#       # - source_labels: [__address__]
#       - source_labels: [__meta_consul_address]
#         target_label: __param_target
#       - source_labels: [__param_target]
#         # target_label: target
#         target_label: instance
# 
#       - target_label: __address__
#         replacement: 192.168.27.123:9115
# 
# 
#       # - source_labels: [__meta_consul_service_metadata_metrics_path]
#        # target_label: __metrics_path__
#         # blackbox binds to public ethernet, not loopback


  - job_name: 'telegraf'
    consul_sd_configs:
      - server: 'dg-pan-01.int.jeddi.org:8500'
        datacenter: 'dg'
        services: ['telegraf', 'windows']

#    relabel_configs:
#      - source_labels: ['__meta_consul_tags']
#        regex: '(.*)http(.*)'
#        action: keep

    metrics_path: /v1/metrics
    params:
      format: ['prometheus']


  # using snmp-exporter container
  - job_name: 'snmp-unifi'
    static_configs:
      - targets:
        - 192.168.27.1
        - 192.168.27.2
        - 192.168.27.3
        - 192.168.27.200
        - 192.168.27.212
        - 192.168.27.229
    metrics_path: /snmp
    params:
      module: [ubiquiti_unifi]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 192.168.27.123:9116

rule_files:
  - /etc/prometheus/rules.d/*.rules
  - /etc/prometheus/rules.d/*.yaml
  - /etc/prometheus/rules.d/*.yml

# remote_write lets us duplicate metrics data out to CortexMetrics on the same host/cluster
remote_write:
  - name: cortex
    url: "http://dg-pan-01.int.jeddi.org:9009/api/v1/push"

EOH
        destination = "local/prometheus.yaml"

      }
    }
  }
}
