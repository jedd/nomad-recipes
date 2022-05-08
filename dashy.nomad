
// Jedd lab - dashy - home lab dashboard

// Refer:  https://dashy.to/docs/quick-start

variables {
  consul_hostname = "dg-pan-01.int.jeddi.org:8500"
}

job "dashy"  {
  datacenters = ["DG"]
  type = "service"

  group "dashy" {
    network {
      port "port_http" {
        to     = 80
      }
    }

#    # Will need a volume for persistence, almost definitely
#    volume "vol_dashy"  {
#      type = "host"
#      source = "vol_dashy"
#      read_only = false
#    }

    restart {
      interval = "10m"
      attempts = 20
      delay    = "30s"
    }

    constraint {
      attribute = "${attr.unique.hostname}"
      value = "dg-pan-01"
    }

    task "dashy" {
      driver = "docker"

#      volume_mount {
#        volume = "vol_dashy"
#        destination = "/mnt/dashy"
#        read_only = false
#      }

      config {
        image = "lissy93/dashy:latest"
        hostname = "dashy"
        dns_servers = ["192.168.27.123"]
        ports = ["port_http"]

        args  = [ 
          ]

        volumes = [ 
#          "local/prestart.sh:/prestart.sh",
#          "local/main.py:/main.py",
        ]

      }

      resources {
        cpu = 500
        # Dashy won't run with 512MB
        memory = 1024
      }

      service {
        name = "dashy"
        port = "port_http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.dashy.rule=Host(`dashy.int.jeddi.org`)",
          "traefik.http.routers.dashy.tls=false",
        ]

      }

      service {
        name = "dashy-web"
        port = "port_http"
        tags = ["traefik.enable=true"]

        check {
          type = "http"
          port = "port_http"
          path = "/"
          interval = "30s"
          timeout = "5s"
        }
      }


    }
  }
}
