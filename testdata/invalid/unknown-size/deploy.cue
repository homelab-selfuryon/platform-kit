package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

// Must be rejected: size outside small|medium|large
app.#App & {
	name: "x"
	team: "t"
	size: "huge"
}
