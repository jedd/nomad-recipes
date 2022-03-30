
//  starlink-exporter for prometheus - for jedd's lab (dg)

# danopstech has kindly put together a docker image that scrapes your Starlink
# router, and exposes it as an OpenTelemetry endpoint.

# Starlink is almost always hard-coded to 192.168.100.1 -- so if you have a different
# subnet (and I use 192.168.27.0/24) you need to set up a static route to point to
# this 100.1 address.  Doing this ensures the Starlink mobile phone app will also work.

job "starlink-exporter" {
  type = "service"
  datacenters = ["DG"]

  group "starlink-exporter" {
    network {
      port "port-starlink" {
        static = 9817 
      }
    }

    task "starlink-exporter" {
      driver = "docker"

      config {
        ports = [ "port-starlink" ]
        # dns_servers = [ "192.168.27.123" ]

        image = "danopstech/starlink_exporter"

        args = [
          "-address",
          "192.168.100.1:9200",
          "-port",
          "9817",
        ]

      }

      service {
        name = "starlink-exporter"
        port = "port-starlink"

//        check {
//          type = "http"
//          port = "http"
//          path = "/"
//          interval = "20s"
//          timeout = "10s"
//        }
      }
    }
  }
}
