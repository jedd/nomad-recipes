
// Jedd lab - basic python 3.9 instance

variables {
  consul_hostname = "dg-pan-01.int.jeddi.org:8500"
}

job "python39"  {
  datacenters = ["DG"]
  type = "service"

  group "python39-basic" {
    network {
      port "port_http" {
        static = 8088
      }
    }

#    volume "vol_python39"  {
#      type = "host"
#      source = "vol_python39"
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

    task "python39-basic" {
      driver = "docker"

#      volume_mount {
#        volume = "vol_python39"
#        destination = "/mnt/python39"
#        read_only = false
#      }

      config {
        image = "python:3.9-bullseye"
        dns_servers = ["192.168.27.123"]
        ports = ["port_http"]
        command = "/local/prestart.sh"
        # args  = [ "3000" ]
        volumes = [ 
#          "local/prestart.sh:/prestart.sh",
#          "local/main.py:/main.py",
        ]
        network_mode = "host"
      }

      resources {
        cpu = 500
        memory = 512
      }

      service {
        name = "python39"
        port = "port_http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.python39.rule=Host(`python39.int.jeddi.org`)",
          "traefik.http.routers.python39.tls=false",
        ]

      }

      service {
        name = "python39-web"
        port = "port_http"
        tags = ["traefik.enable=true"]

        check {
          type = "http"
          port = "port_http"
          path = "/services"
          interval = "30s"
          timeout = "5s"
        }
      }

      # = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
      #  FILE:   prestart.sh
      #  This is our entry point - prepares the environment and launches the python script.
      template {
        data = <<EOH
#! /usr/bin/env bash
pip install flask
python3 /local/main.py
EOH
        destination = "local/prestart.sh"
        perms = "755"
      }

      # = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
      #  FILE:   main.py 
      #  Actual target application - launched by prestart.sh (above).
      template {
        data = <<EOH
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello World from Flask on Python3 on Nomad"

if __name__ == "__main__":
    # Only for debugging while developing
    app.run(host='0.0.0.0', debug=True, port=8088)

EOH
        destination = "local/main.py"
      }

    }
  }
}
