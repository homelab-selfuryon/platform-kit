package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: egress FQDN that is not a host name
app.#App & {
	name: "x"
	team: "t"
	network: egressFQDN: [{host: "*.example.org"}]
}
