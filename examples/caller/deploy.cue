package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// The client side: calls another app with a projected token, not public.
app.#App & {
	name: "caller"
	team: "examples"
	network: calls: [{app: "api", port: 9000}]
}
