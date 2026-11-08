package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: a field the schema does not know
app.#App & {
	name:     "x"
	team:     "t"
	replicas: 3
}
