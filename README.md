Hashicorp's Nomad is an orchestration tool for containerised workloads - think of it as k8s for busy mortals.

It's reasonably popular, though collections of recipes are thin on the ground -- so this is my small contribution.

I hasten to qualify that with the usual caveat that _'these recipes work, at least in my environment, but are certainly not likely, let alone guaranteed, to be best practice'_.

There's a collection of .nomad files (the actual job definitions themselves) as well as copies or extracts of my docker and nomad daemon configuration files -- the latter are under the ./etc/ directory.

My lab was a single Debian sid host, but then grew to a Nomad server/client + 3 clients.  All machines share various NFS mounts, which is how I get mobility between the servers.

In any case, you WILL naturally need to adjust constraints and cpu/memory allocations to suit your environment.

My 3 x client nodes have a wildcard DNS to ``*.obs.int.jeddi.org``, and I use Traefik to route traffic to that cluster.

I utilise Hashicorp Consul as well, partly for its key-value functionality but also for service mesh for my Prometheus scrape targets.

Finally, note that Hashicorp is building out a registry using Nomad Pack - available at: https://github.com/hashicorp/nomad-pack-community-registry however as of mid-2022 it could still be considered inchoate. These Nomad Packs use a template (.tpl) with metadata & variables (.hcl) combo, and while this abstraction is certainly much more Enterprisey, it's less readable IMO.


2025 additional notes

I run two lab sites, but they both use `int.jeddi.org` for their domain, both with letsencrypt certs - and the Nomad clusters in both locations also have their own (via local DNS) `obs.int.jeddi.org` with valid SSL certs, managed by Traefik.

I'm using the env var `NOMAD_VAR_nomad_dc=DG` approach at my two sites (PY, DG) so that more of my jobs can be run at either location, and they work out where they are from that variable. This works well, and jobs that can really only be run at one site (due to compute requirements, say) just hard code the DC constraint.

