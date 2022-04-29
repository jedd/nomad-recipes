# Refer:
#  https://grafana.com/docs/mimir/latest/operators-guide/configuring/reference-configuration-parameters/

# NOT WORKING - initial commit, work in progress, etc
# NOT WORKING - initial commit, work in progress, etc
# NOT WORKING - initial commit, work in progress, etc

// @TODO
// Add entrypoints to Traefik job
// S3 config for the store-gateway and ingester
// Correct all network port values


// Each component or module is invoked using its -target parameter ie -target=compactor
// server module is loaded with each module by default if it is needed

// Required Group Modules and the components they load by default
// compactor + server, memberlist-kv modules, sanity-checker, activity-tracker
// distributor + server, activity-tracker, memberlist-kv, ring modules, sanity-checker 
// ingester + activity-tracker, server, sanity-check, memberlist-kv, ingester-service
// querier + server, activity-tracker, memberlist-kv, store-queryable, ring
// querier-frontend + sanity-check, activity-tracker, server, query-frontend
// store-gateway + sanity-check, activity-tracker, server, memberlist-kv, store-gateway

job "mimir-distributed" {
  datacenters = ["DG"]


  group "query-frontend" {
        network {
            port "grpc" {
              to = 10902
            }
            port "http" {
              to = 10901
            }
        }
    
    service {
        name = "query-frontend"
        port = "grpc"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.mimir.rule=Host(`mimir.int.jeddi.org`)",
          "traefik.http.routers.mimir.tls=false",
          "traefik.http.routers.mimir.entrypoints=http,https,mimir",
        ]
    }

    task "query-frontend" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=query-frontend",
          "-server.http-listen-port=10901"
        ]
      }
      resources {
        cpu    = 500
        memory = 256
      }         
    }
  }
  group "compactor" {
        network {
            port "grpc" {}
            port "http" {}
        }
    
    service {
        name = "compactor"
        port = "grpc"
        tags = ["grpc","http"]
    }

    task "compactor" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=compactor",
          "-compactor.ring.store=consul",
          "-compactor.ring.prefix=collectors/",
          "-compactor.ring.consul.acl-token=REDACTED",
          "-compactor.ring.consul.hostname=consul.service.dg.collectors.int.jeddi.org:8500"          
        ]
      }
      resources {
        cpu    = 500
        memory = 256
      }         
    }
  }
  group "distributor" {
    count = 3
        network {
            port "grpc" {}
            port "http" {}
        }
    
    service {
        name = "distributor"
        port = "grpc"
        tags = ["grpc","http"]
    }

    task "distributor" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=distributor",
          "-server.grpc-listen-port=${NOMAD_PORT_http}",
          "-distributor.ring.store=consul",
          "-distributor.ring.prefix=collectors/",
          "-distributor.ring.consul.acl-token=REDACTED",
          "-distributor.ring.consul.hostname=consul.service.dg.collectors.int.jeddi.org8500"
        ]
      }
      resources {
        cpu    = 500
        memory = 256
      }       
    }
  }
  group "ingester" {
        network {
            port "grpc" {}
            port "http" {}
        }
    
    service {
        name = "ingester"
        port = "grpc"
        tags = ["grpc","http"]
    }

    task "ingester" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=ingester",
          "-server.grpc-listen-port=${NOMAD_PORT_http}",
          "-ingester.ring.store=consul",
          "-ingester.ring.prefix=collectors/",
          "-ingester.ring.consul.acl-token=REDACTED",
          "-ingester.ring.consul.hostname=consul.service.dg.collectors.int.jeddi.org:8500",
        ]
      }
      resources {
        cpu    = 500
        memory = 256
      }         
    }
  }     
  group "store-gateway" {
        network {
            port "grpc" {}
            port "http" {}
        }
    
    service {
        name = "store-gateway"
        port = "grpc"
        tags = ["grpc","http"]
    }

    task "store-gateway" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=store-gateway",
          "-store-gateway.sharding-ring.store=consul",
          "-store-gateway.sharding-ring.prefix=collectors/",
          "-store-gateway.sharding-ring.consul.acl-token=REDACTED",
          "-store-gateway.sharding-ring.consul.hostname=consul.service.dg.collectors.int.jeddi.org:8500"
        ]
      }
      resources {
        cpu    = 500
        memory = 256
      }         
    }
  }   
  group "querier" {
        network {
            port "grpc" {}
            port "http" {}
        }
    
    service {
        name = "querier"
        port = "grpc"
        tags = ["grpc","http"]
    }

    task "querier" {
      driver = "docker"

      config {
        image = "grafana/mimir:latest"
        dns_servers = ["192.168.31.1"]
        args = [
          "-target=querier"
        ]
      }   
      resources {
        cpu    = 500
        memory = 256
      }
    }    
  }  
}
