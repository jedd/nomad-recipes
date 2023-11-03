Hashicorp's Nomad is an orchestration tool for containerised workloads - think of it as k8s for busy mortals.

It's reasonably popular, though collections of recipes are thin on the ground -- so this is my small contribution.

I hasten to qualify that with the usual caveat that _'these recipes work, at least in my environment, but are certainly not likely, let alone guaranteed, to be best practice'_.

There's a collection of .nomad files (the actual job definitions themselves) as well as copies or extracts of my docker and nomad daemon configuration files -- the latter are under the ./etc/ directory.

My lab was a single Debian sid host, but then grew to a Nomad server/client + 3 clients.  All machines share various NFS mounts, which is how I get mobility between the servers.

In any case, you WILL naturally need to adjust constraints and cpu/memory allocations to suit your environment.

My 3 x client nodes have a wildcard DNS to ``*.obs.int.jeddi.org``, and I use Traefik to route traffic to that cluster.

I utilise Hashicorp Consul as well, partly for its key-value functionality but also for service mesh for my Prometheus scrape targets.

Finally, note that Hashicorp is building out a registry using Nomad Pack - available at: https://github.com/hashicorp/nomad-pack-community-registry however as of mid-2022 it could still be considered inchoate. These Nomad Packs use a template (.tpl) with metadata & variables (.hcl) combo, and while this abstraction is certainly much more Enterprisey, it's less readable IMO.

