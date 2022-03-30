## https://www.consul.io/docs/agent/options.html#client_addr


bind_addr = "192.168.27.123"

# client_addr = "192.168.1.10"
client_addr = "127.0.0.1 {{ GetPrivateIPs }}"

## https://www.consul.io/docs/agent/options.html#retry_join

# Previously configured to be a two-node cluster.  
# This was a poor choice of configuration.
# retry_join = ["dg-pan-01.int.jeddi.org", "jarre.int.jeddi.org"]
retry_join = ["dg-pan-01.int.jeddi.org"]
