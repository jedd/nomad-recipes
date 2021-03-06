Hashicorp's Nomad is an easier-to-use-than-k8s container orchestration (and more) suite.

However collections of recipes are thin on the ground, so this is my small contribution.

I hasten to qualify that with 'these recipes work, at least in my environment, but are certainly not likely, let alone guaranteed, to be best practice'.

There's a collection of .nomad files (the actual job definitions themselves) as well as copies or extracts of my docker and nomad daemon configuration files -- the latter are under the ./etc/ directory.

Note that in my lab I run these on single a Debian sid host.

I have Hashicorp Consul in play, for some key-value functions primarily, and also utilise Traefik (though not extensively, as for a single box there's not much benefit).

Note that Hashicorp is building out a registry using Nomad Pack - available at: https://github.com/hashicorp/nomad-pack-community-registry however as of mid-2022 it could still be considered inchoate. These Nomad Packs use a template (.tpl) with metadata & variables (.hcl) combo, and while this abstraction is certainly much more Enterprisey, it's less readable IMO.

