package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: port out of range
app.#App & {
	name: "x"
	team: "t"
	port: 70000
}
