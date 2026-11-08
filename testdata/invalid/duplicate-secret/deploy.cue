package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: the same secret twice
app.#App & {
	name:    "x"
	team:    "t"
	secrets: ["a", "a"]
}
