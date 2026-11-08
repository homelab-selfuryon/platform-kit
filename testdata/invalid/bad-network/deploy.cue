package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: unknown network option
app.#App & {
	name: "x"
	team: "t"
	network: allowAll: true
}
