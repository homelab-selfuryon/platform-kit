// Package env defines the environments an app is rendered for: namespace
// pattern, hostnames, replicas, the PodDisruptionBudget and the database
// topology. An environment is data; the schema in package app reads it.
package env

// domain is a placeholder until a real domain is chosen (meta/decisions.md).
domain: "homelab.example"

#Name: "preview" | "staging" | "prod"

// #Spec is what differs between environments.
#Spec: {
	name: #Name
	// replicas of every Deployment.
	replicas: int & >=1
	// pdb: render a PodDisruptionBudget.
	pdb: bool
	// dbInstances: CloudNativePG instances per database.
	dbInstances: int & >=1
	// gateway: name of the Gateway in envoy-gateway-system, one per environment.
	gateway: name
}

#Environments: {
	preview: #Spec & {name: "preview", replicas: 1, pdb: false, dbInstances: 1}
	staging: #Spec & {name: "staging", replicas: 1, pdb: false, dbInstances: 1}
	prod:    #Spec & {name: "prod", replicas: 2, pdb: true, dbInstances: 1}
}

// #Size maps the T-shirt size of an app to resources. CPU limits are
// deliberately absent: they throttle without protecting anybody.
#Size: "small" | "medium" | "large"

#Sizes: {
	small: {
		requests: {cpu: "50m", memory: "64Mi"}
		limits:   {memory: "128Mi"}
		db: {
			storage:  "1Gi"
			requests: {cpu: "100m", memory: "256Mi"}
			limits:   {memory: "512Mi"}
		}
	}
	medium: {
		requests: {cpu: "100m", memory: "128Mi"}
		limits:   {memory: "256Mi"}
		db: {
			storage:  "5Gi"
			requests: {cpu: "250m", memory: "512Mi"}
			limits:   {memory: "1Gi"}
		}
	}
	large: {
		requests: {cpu: "250m", memory: "256Mi"}
		limits:   {memory: "512Mi"}
		db: {
			storage:  "20Gi"
			requests: {cpu: "500m", memory: "1Gi"}
			limits:   {memory: "2Gi"}
		}
	}
}

// #Place is where one app of one team runs in one environment.
//
//	namespace  preview <team>-pr-<n>, staging <team>-staging, prod <team>-prod
//	host       preview <svc>-pr-<n>.preview.<domain>, staging <svc>.staging.<domain>,
//	           prod <svc>.<domain>
#Place: {
	team: string
	app:  string
	env:  #Name
	// pr is the pull request number; required for preview.
	pr?: int & >0

	namespace: string
	host:      string

	if env == "preview" {
		pr:        int & >0
		namespace: "\(team)-pr-\(pr)"
		host:      "\(app)-pr-\(pr).preview.\(domain)"
	}
	if env == "staging" {
		namespace: "\(team)-staging"
		host:      "\(app).staging.\(domain)"
	}
	if env == "prod" {
		namespace: "\(team)-prod"
		host:      "\(app).\(domain)"
	}
}

// #CallTarget: where the apps an app calls live. Preview has no
// siblings in its own namespace, so it talks to staging.
#CallTarget: {
	team:      string
	env:       #Name
	namespace: string
	if env == "preview" {
		namespace: "\(team)-staging"
	}
	if env != "preview" {
		namespace: "\(team)-\(env)"
	}
}
