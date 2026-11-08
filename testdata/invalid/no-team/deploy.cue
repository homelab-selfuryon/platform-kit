package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: missing team
app.#App & {
	name: "x"
}
