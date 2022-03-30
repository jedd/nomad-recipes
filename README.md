Hashicorp's Nomad is an easier-to-use-than-k8s container (and more) suite.

However, recipes are thin on the ground, so this is my small contribution.

There's a collection of .nomad files (the actual job definitions themselves) as well as copies or extracts of my docker and nomad daemon configuration files -- the latter are under the ./etc/ directory.

Note that in my lab I run these on single a Debian sid host.

I have Hashicorp Consul in play, for some key-value functions primarily, and also utilise Traefik (though not extensively, as for a single box there's not much benefit).

