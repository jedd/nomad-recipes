 
// Collector-proxmox

// Combined standalone prometheus + exporter (proxmox)

// (In my work environment, we have adopted a convention of 'collector' 
// being whatever task(s) are required to query a custom service - often 
// using blackbox or another Prometheus exporter, paired with Prometheus.)

variables {
  image_prometheus = "https://docker.io/prom/prometheus:v2.41.0"
  image_proxmox = "prompve/prometheus-pve-exporter:3.4.1"
}


# JOB collector-proxmox = = = = = = = = = = = = = = = = = = = = = = = = =
job "collector-proxmox" {
  type = "service"
  datacenters = ["DG"]

  group "collector-proxmox" {
    
    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

		constraint {
			attribute = "${attr.unique.hostname}"
			operator = "regexp"
			value = "dg-hac-0[123]"
		}

    network {
      port "port_prometheus" { }
      port "port_exporter_proxmox" { }
    }


    # TASK prometheus = = = = = = = = = = = = = = = = = = = = = = = = =
    task "task-prometheus" {
      driver = "docker"

      config {
        image = "${var.image_prometheus}"

        args = [
          "--web.listen-address=0.0.0.0:${NOMAD_PORT_port_prometheus}",
          "--web.page-title=Prometheus for Proxmox Collector",
          # "--enable-feature=agent",
          "--config.file=/etc/prometheus/prometheus.yml"
        ]

        dns_servers = ["192.168.27.123", "192.168.27.1"]

        logging {
          type = "loki"
          config {
            loki-url = "http://loki.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }        

        volumes = [ 
          "local/prometheus.yaml:/etc/prometheus/prometheus.yml",
        ]

        network_mode = "host"
      }

      resources {
        cpu    = 100
        memory = 150
      }

      service {
        name = "collector-proxmox-prometheus"
        port = "port_prometheus"
#        check {
#          type = "http"
#          port = "port_prometheus"
#          path = "/-/healthy"
#          interval = "20s"
#          timeout = "10s"
#        }

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prometheus-proxmox.entrypoints=http,https",
          "traefik.http.routers.prometheus-proxmox.rule=Host(`prometheus-proxmox.obs.int.jeddi.org`)",
          "traefik.http.routers.prometheus-proxmox.tls=false"
        ]
      }

      template {
        data = <<EOH

global:
  external_labels:
    nomad_job_name: {{ env "NOMAD_JOB_NAME" }}
    nomad_task_name: {{ env "NOMAD_TASK_NAME" }}

  scrape_interval: 1m

  # This creates a log of *all* queries, and will show up in /metrics as 
  #     prometheus_engine_query_log_enabled=1
  query_log_file:  /prometheus/query.log

scrape_configs:
  - job_name: 'prometheus_proxmox'
    metrics_path: /metrics
    static_configs:
      - targets: [ "prometheus-proxmox.obs.int.jeddi.org" ]

  - job_name: 'exporter_proxmox'
    metrics_path: /pve
    static_configs:
      - targets:
        - 192.168.27.113
    params:
      module: [default]
      cluster: ['1']
      node: ['1']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: exporter-proxmox.obs.int.jeddi.org

remote_write:
  - name: mimir
    url: "http://dg-pan-01.int.jeddi.org:19009/api/v1/push"

EOH
        destination = "local/prometheus.yaml"
      }
    }


    # TASK exporter proxmox   = = = = = = = = = = = = = = = = = = = = = = = = =
    task "exporter-proxmox" {
      driver = "docker"

      config {
        ports = [ "port_exporter_proxmox" ]

        image = "${var.image_proxmox}"

        args = [
          "--config.file", "/etc/pve.yml",
          "--web.listen-address", "0.0.0.0:${NOMAD_PORT_port_exporter_proxmox}"
        ]

        dns_servers = ["192.168.27.123", "192.168.27.1"]

        logging {
          type = "loki"
          config {
            loki-url = "http://loki.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }        

        volumes = [
          "local/pve.yml:/etc/pve.yml",
        ]
      }

      resources {
        cpu    = 100
        memory = 150
      }

      service {
        name = "exporter-proxmox"
        port = "port_exporter_proxmox"

#        check {
#          type = "http"
#          port = "port_exporter_proxmox"
#          path = "/-/healthy"
#          interval = "20s"
#          timeout = "10s"
#        }

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.exporter-proxmox.entrypoints=http,https",
          "traefik.http.routers.exporter-proxmox.rule=Host(`exporter-proxmox.obs.int.jeddi.org`)",
          "traefik.http.routers.exporter-proxmox.tls=false"
        ]
      }

      template {
        data = <<EOH
default:
    user: monitor@pve
    password: secretpassword

		# Could not get token_name format right - seems to both need, and choke on, the x@pve format
    # token_name: monitoring_token@pve
    # token_value: abcdef01-2345-4175-8d95-7299590afefe

    verify_ssl: false

EOH
        destination = "local/pve.yml"
      }

    } // end-task-exporter-proxmox

  }

}

