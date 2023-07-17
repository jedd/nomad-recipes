
//  snmp-exporter for prometheus - for jedd's lab (dg)

job "snmp-exporter" {
  type = "service"
  datacenters = ["DG"]

  group "snmp-exporter" {
    network {
      port "snmp-exporter" {
        static = 9116 
      }
    }

    task "snmp-exporter" {
      driver = "docker"

      config {
        ports = [
          "snmp-exporter"
          ]
        image = "docker.io/prom/snmp-exporter:latest"
        dns_servers = [ "192.168.27.123" ]
        volumes = [
          "local/snmp_exporter.yaml:/etc/snmp_exporter.yaml"
        ]
        logging  {
          type = "loki"
          config {
            loki-url = "http://dg-pan-01.int.jeddi.org:3100/loki/api/v1/push"
            loki-external-labels = "job=${NOMAD_JOB_ID},task=${NOMAD_TASK_NAME}"
          }
        }
      }

      service {
        name = "snmp-exporter"
        port = "snmp-exporter"
//
//        check {
//          type = "http"
//          port = "http"
//          path = "/"
//          interval = "20s"
//          timeout = "10s"
//        }
      }

      template {
        data = <<EOH
modules:
  prober: https
  timeout: 10s

EOH
        destination = "local/snmp_exporter.yaml"
      }
    }

  }
}
