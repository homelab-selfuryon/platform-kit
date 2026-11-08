package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: env key that is not UPPER_SNAKE
app.#App & {
	name: "x"
	team: "t"
	env: "log-level": "info"
}
