package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: env overriding a value the platform sets
app.#App & {
	name: "x"
	team: "t"
	env: PORT: "1"
}
