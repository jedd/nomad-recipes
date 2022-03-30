
plugin "docker" {
  config {
    allow_privileged = true
    allow_caps = [ "net_raw", "net_admin" ]
    }
  }
