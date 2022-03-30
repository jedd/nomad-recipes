# Nomad client & Server configuration

data_dir = "/var/lib/nomad/"

datacenter = "DG"

client {
  enabled = true
  options {
    "docker.volumes.enabled" = "true"
  }

  ### Single node
  servers = ["192.168.27.123"]

  host_volume "loki" {
    path = "/opt/loki"
    read_only = false
  }

  host_volume "promvol" {
    path = "/opt/prometheus"
    read_only = false
  }

  host_volume "promconfvol" {
    path = "/opt/prometheus-configuration"
    read_only = false
  }

  host_volume "vol_cortex" {
    path = "/opt/cortex"
    read_only = false
  }

  host_volume "vol_tempo" {
    path = "/opt/tempo"
    read_only = false
  }

  host_volume "vol_nodered" {
    path = "/opt/nodered"
    read_only = false
  }

  host_volume "vol_postgresql" {
    path = "/opt/postgresql"
    read_only = false
  }

  host_volume "vol_timescaledb" {
    path = "/opt/timescaledb"
    read_only = false
  }

  host_volume "vol_var_log" {
    path = "/var/log"
    read_only = true
  }

  host_volume "vol_plausible_postgres" {
    path = "/opt/plausible_postgres"
    read_only = false
  }

}

bind_addr = "0.0.0.0"

advertise {
  # This should be the IP of THIS MACHINE and must be routable by every node
  # in the cluster
  rpc = "192.168.27.123:4647"
}

server {
  enabled          = true
  # bootstrap_expect = the number of servers to wait for before bootstrapping - typically
  # an odd number
  bootstrap_expect = 1
}

# We can retrieve opentelemetry (prometheus-style) metrics direct from Nomad.
telemetry {
  collection_interval = "10s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

