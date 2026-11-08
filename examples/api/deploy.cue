package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Everything on the server side: public, database, secrets, a caller, the
// kube-apiserver for token verification, and a non-default size and port.
app.#App & {
	name:   "api"
	team:   "examples"
	port:   9000
	size:   "medium"
	public: true
	database: postgres: {}
	secrets: ["example-key", "other.key"]
	env: LOG_LEVEL: "debug"
	network: {
		allowFrom:  [{app: "caller"}]
		egressFQDN: [{host: "api.example.org"}, {host: "mirror.example.org", port: 8443}]
		kubeAPI:    true
	}
}
