package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: name with an uppercase letter
app.#App & {
	name: "Bad_Name"
	team: "t"
}
