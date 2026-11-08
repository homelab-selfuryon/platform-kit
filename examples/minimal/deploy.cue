package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// The smallest app: no ingress, no database, no secrets.
app.#App & {
	name: "minimal"
	team: "examples"
}
