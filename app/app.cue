// Package app is the schema of an app's deploy.cue and its render to
// Kubernetes objects.
//
//	package deploy
//	import "github.com/homelab-selfuryon/platform-kit/app"
//	app.#App & {name: "notes-api", team: "notes", ...}
//
// CI adds deploy/context_gen.cue (package deploy, field `context`) and reads
// the objects of one environment with
//
//	cue export ./deploy -e manifestsYAML --out text
package app

import (
	"encoding/yaml"
	"strings"
	apps_v1 "cue.dev/x/k8s.io/api/apps/v1"
	core_v1 "cue.dev/x/k8s.io/api/core/v1"
	policy_v1 "cue.dev/x/k8s.io/api/policy/v1"
	"github.com/homelab-selfuryon/platform-kit/crd"
	"list"
	envdef "github.com/homelab-selfuryon/platform-kit/env"
)

// #Name is a DNS label that leaves room for the suffixes the platform adds
// (`-db`, `-pr-<n>`).
#Name: =~"^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$"

#Team: =~"^[a-z]([a-z0-9-]{0,18}[a-z0-9])?$"

// #Peer names another app: the one that may call this one (allowFrom) or
// the one this app calls. The team defaults to the team of this app.
#Peer: {
	app:   #Name
	team?: #Team
	// port the peer's container listens on (calls only).
	port: *8080 | (int & >0 & <65536)
}

// #FQDN is an external destination, TCP only.
#FQDN: {
	host: =~"^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
	port: *443 | (int & >0 & <65536)
}

// #Context is written by CI for one environment.
#Context: {
	env: envdef.#Name
	// image by digest.
	image:   =~"^[a-z0-9./_-]+(:[A-Za-z0-9._-]+)?@sha256:[a-f0-9]{64}$"
	version: =~"^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$"
	// pr is the pull request number, preview only.
	pr?: int & >0
	if env == "preview" {
		pr: int & >0
	}
}

// #App is what deploy.cue unifies with: the fields a team writes. Until CI adds `context`
// (deploy/context_gen.cue) it is only the schema; with it, `objects` and `manifestsYAML` are the
// render for that environment.
#App: {
	// name of the app: Deployment, Service, ServiceAccount, host name.
	name: #Name
	// team that owns the app (GitHub team of the same name).
	team: #Team
	// port of the container; the Service listens on 80.
	port: *8080 | (int & >0 & <65536)
	// size selects requests and limits, see package env.
	size: *"small" | envdef.#Size
	// public renders an HTTPRoute on the environment's Gateway.
	public: *false | bool
	// database renders a CloudNativePG cluster; credentials are files under
	// /var/run/secrets/db/.
	database?: postgres: {}
	// secrets are keys under kv/<team>/<env>/<name>/ in OpenBao, mounted as
	// files in /var/run/secrets/app/<key>.
	secrets: *[] | [...=~"^[A-Za-z0-9._-]{1,64}$"]
	// env is non-secret configuration. PORT, APP_ENV, APP_VERSION, AUTH_AUDIENCE and
	// AUTH_ALLOWED_SUBJECTS are set by the platform.
	env: {[=~"^[A-Z][A-Z0-9_]*$" & !~"^(PORT|APP_ENV|APP_VERSION|AUTH_AUDIENCE|AUTH_ALLOWED_SUBJECTS)$"]: string}
	network: {
		// allowFrom: apps that may reach this one.
		allowFrom: *[] | [...#Peer]
		// calls: apps this one calls: egress plus a projected token whose
		// audience is the callee's name.
		calls:      *[] | [...#Peer]
		egressFQDN: *[] | [...#FQDN]
		// kubeAPI: egress to the kube-apiserver and a token to authenticate to
		// it, e.g. to fetch the JWKS that verifies callers' tokens.
		kubeAPI: *false | bool
	}

	// Duplicate secrets would collide as file names.
	_uniqueSecrets: true & list.UniqueItems(secrets)

	// context is written by CI.
	context?: #Context

	// objects of the environment in `context`, in apply order, and manifestsYAML, the
	// multi-document stream the workflows publish. Absent without a context.
	objects?:       _
	manifestsYAML?: _

	// The inputs under other names: a field `name: name` would refer to itself.
	let _name = name
	let _team = team
	let _port = port
	let _size = size
	let _public = public
	let _secrets = secrets
	let _env = env
	let _network = network
	if context != _|_ {
		let _ctx = context
		let _r = #Render & {
			in: {
				name:    _name
				team:    _team
				port:    _port
				size:    _size
				public:  _public
				secrets: _secrets
				env:     _env
				network: _network
				if database != _|_ {
					database: database
				}
			}
			context: _ctx
		}
		objects:       _r.objects
		manifestsYAML: _r.manifestsYAML
	}
}

#Render: {
	in:      _
	context: #Context

	objects:       _objects
	manifestsYAML: _manifestsYAML

	let _svc = in.name
	let _team = in.team
	let _port = in.port
	let _ctx = context
	let _spec = envdef.#Environments[_ctx.env]
	let _size = envdef.#Sizes[in.size]
	let _place = envdef.#Place & {
		team: _team
		app:  _svc
		env:  _ctx.env
		if _ctx.pr != _|_ {pr: _ctx.pr}
	}
	let _hasDB = in.database != _|_
	let _hasSecrets = len(in.secrets) > 0

	let _selector = {"app.kubernetes.io/name": _svc}
	let _podLabels = {
		_selector
		"app.kubernetes.io/part-of":        _team
		"app.kubernetes.io/managed-by":     "platform-kit"
		"homelab-selfuryon.github.io/team": _team
		"homelab-selfuryon.github.io/env":  _ctx.env
		if _ctx.env == "preview" {
			"homelab-selfuryon.github.io/pr": "\(_ctx.pr)"
		}
	}
	let _labels = {
		_podLabels
		"app.kubernetes.io/version": _ctx.version
	}

	// Peers with the team filled in.
	_allow: [for p in in.network.allowFrom {
		app: p.app
		let t = *p.team | _team
		namespace: (envdef.#Place & {
			team: t
			app:  p.app
			env:  _ctx.env
			if _ctx.pr != _|_ {pr: _ctx.pr}
		}).namespace
	}]
	_calls: [for p in in.network.calls {
		app:  p.app
		port: p.port
		let t = *p.team | _team
		namespace: (envdef.#CallTarget & {team: t, env: _ctx.env}).namespace
		// URL of the callee's Service (port 80).
		url: "http://\(p.app).\(namespace).svc.cluster.local"
	}]

	// ------------------------------------------------------------- env vars
	_platformEnv: {
		PORT:        "\(_port)"
		APP_ENV:     _ctx.env
		APP_VERSION: _ctx.version
		// Verification of callers' tokens (see rust-app-template).
		if len(_allow) > 0 {
			AUTH_AUDIENCE:         _svc
			AUTH_ALLOWED_SUBJECTS: strings.Join([for a in _allow {"system:serviceaccount:\(a.namespace):\(a.app)"}], ",")
		}
		for c in _calls {
			"\(strings.Replace(strings.ToUpper(c.app), "-", "_", -1))_URL": c.url
		}
	}
	// A user value that collides with a platform value is an error (the schema refuses the fixed names,
	// a clash with a `<CALLEE>_URL` is a conflict here).
	_allEnv: {
		for k, v in _platformEnv {(k): v}
		for k, v in in.env {(k): v}
	}

	// -------------------------------------------------------------- volumes
	let _kubeAPIDir = "/var/run/secrets/kube-api"
	_volumes: [
		{name: "tmp", emptyDir: sizeLimit: "64Mi"},
		if _hasSecrets {
			name: "secrets"
			csi: {
				driver:   "secrets-store.csi.k8s.io"
				readOnly: true
				volumeAttributes: secretProviderClass: _svc
			}
		},
		if _hasDB {
			name: "db"
			secret: {
				secretName:  "\(_svc)-db-app"
				defaultMode: 0o440
			}
		},
		for c in _calls {
			name: "token-\(c.app)"
			projected: {
				defaultMode: 0o440
				sources: [{
					serviceAccountToken: {
						audience:          c.app
						expirationSeconds: 3600
						path:              "token"
					}
				}]
			}
		},
		if in.network.kubeAPI {
			name: "kube-api"
			projected: {
				defaultMode: 0o440
				sources: [
					// No audience: the kube-apiserver's own default.
					{serviceAccountToken: {expirationSeconds: 3600, path: "token"}},
					{configMap: {name: "kube-root-ca.crt", items: [{key: "ca.crt", path: "ca.crt"}]}},
				]
			}
		},
	]
	_mounts: [
		{name: "tmp", mountPath: "/tmp"},
		if _hasSecrets {name: "secrets", mountPath: "/var/run/secrets/app", readOnly: true},
		if _hasDB {name: "db", mountPath: "/var/run/secrets/db", readOnly: true},
		for c in _calls {name: "token-\(c.app)", mountPath: "/var/run/secrets/tokens/\(c.app)", readOnly: true},
		if in.network.kubeAPI {name: "kube-api", mountPath: _kubeAPIDir, readOnly: true},
	]

	// ------------------------------------------------------------- objects
	_serviceAccount: core_v1.#ServiceAccount & {
		metadata:                     {name: _svc, labels: _labels}
		automountServiceAccountToken: false
	}

	_deployment: apps_v1.#Deployment & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			replicas:             _spec.replicas
			revisionHistoryLimit: 3
			selector: matchLabels: _selector
			strategy: {
				type:          "RollingUpdate"
				rollingUpdate: {maxUnavailable: 0, maxSurge: 1}
			}
			template: {
				metadata: labels: _podLabels
				spec: {
					serviceAccountName:            _svc
					automountServiceAccountToken:  false
					enableServiceLinks:            false
					terminationGracePeriodSeconds: 30
					securityContext: {
						runAsNonRoot: true
						runAsUser:    #Cluster.uid
						runAsGroup:   #Cluster.uid
						fsGroup:      #Cluster.uid
						seccompProfile: type: "RuntimeDefault"
					}
					if _spec.replicas > 1 {
						topologySpreadConstraints: [{
							maxSkew:           1
							topologyKey:       "kubernetes.io/hostname"
							whenUnsatisfiable: "ScheduleAnyway"
							labelSelector: matchLabels: _selector
						}]
					}
					containers: [{
						name:            "app"
						image:           _ctx.image
						imagePullPolicy: "IfNotPresent"
						ports:           [{name: "http", containerPort: _port, protocol: "TCP"}]
						env:             [for k, v in _allEnv {name: k, value: v}]
						securityContext: {
							privileged:               false
							allowPrivilegeEscalation: false
							readOnlyRootFilesystem:   true
							runAsNonRoot:             true
							capabilities: drop:   ["ALL"]
							seccompProfile: type: "RuntimeDefault"
						}
						resources: {
							requests: _size.requests
							limits:   _size.limits
						}
						livenessProbe: {
							httpGet:          {path: "/healthz", port: "http"}
							periodSeconds:    10
							timeoutSeconds:   2
							failureThreshold: 3
						}
						readinessProbe: {
							httpGet:          {path: "/readyz", port: "http"}
							periodSeconds:    5
							timeoutSeconds:   2
							failureThreshold: 3
						}
						startupProbe: {
							httpGet:          {path: "/healthz", port: "http"}
							periodSeconds:    2
							failureThreshold: 30
						}
						volumeMounts: _mounts
					}]
					volumes: _volumes
				}
			}
		}
	}

	_service: core_v1.#Service & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			type:     "ClusterIP"
			selector: _selector
			ports:    [{name: "http", port: 80, targetPort: "http", protocol: "TCP", appProtocol: "http"}]
		}
	}

	_pdb: policy_v1.#PodDisruptionBudget & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			minAvailable: 1
			selector: matchLabels: _selector
		}
	}

	_route: crd.#HTTPRoute & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			parentRefs: [{
				name:        _spec.gateway
				namespace:   #Cluster.gatewayNamespace
				sectionName: #Cluster.gatewayListener
			}]
			hostnames: [_place.host]
			rules: [{
				matches:     [{path: {type: "PathPrefix", value: "/"}}]
				backendRefs: [{name: _svc, port: 80}]
			}]
		}
	}

	let _dbSelector = {"cnpg.io/cluster": "\(_svc)-db"}

	_database: crd.#CNPGCluster & {
		metadata: {name: "\(_svc)-db", labels: _labels}
		spec: {
			instances: _spec.dbInstances
			// PostgreSQL image from the platform's catalog (the cluster refuses anything else).
			imageCatalogRef: {
				apiGroup: "postgresql.cnpg.io"
				kind:     "ClusterImageCatalog"
				name:     #Cluster.postgresCatalog
				major:    #Cluster.postgresMajor
			}
			enableSuperuserAccess: false
			// No storageClass: the cluster default.
			storage: size: _size.db.storage
			resources: {
				requests: _size.db.requests
				limits:   _size.db.limits
			}
		}
	}

	_secretProviderClass: crd.#SecretProviderClass & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			provider: "openbao"
			parameters: {
				baoAddress:             #Cluster.openbao
				baoKubernetesMountPath: #Cluster.openbaoMount
				roleName:               "\(_team)-\(_ctx.env)-\(_svc)"
				// Written as text: the provider reads filePermission as an octal literal,
				// which a YAML encoder would turn into its decimal value.
				objects: strings.Join([for s in in.secrets {
					"- objectName: \"\(s)\"\n  secretPath: \"\(#Cluster.openbaoKV)/data/\(_team)/\(_ctx.env)/\(_svc)/\(s)\"\n  secretKey: \"value\"\n  filePermission: 0440\n"
				}], "")
			}
		}
	}

	let _dns = {
		toEndpoints: [{
			matchLabels: {
				"k8s:io.kubernetes.pod.namespace": "kube-system"
				"k8s:k8s-app":                     "kube-dns"
			}
		}]
		toPorts: [{
			ports: [{port: "53", protocol: "ANY"}]
			rules: dns: [{matchPattern: "*"}]
		}]
	}

	_networkPolicy: crd.#CiliumNetworkPolicy & {
		metadata: {name: _svc, labels: _labels}
		spec: {
			endpointSelector: matchLabels: _selector
			let _in = [
				if in.public {
					fromEndpoints: [{
						matchLabels: {
							"k8s:io.kubernetes.pod.namespace":           #Cluster.gatewayNamespace
							"k8s:homelab-selfuryon.github.io/component": "gateway-proxy"
						}
					}]
					toPorts: [{ports: [{port: "\(_port)"}]}]
				},
				if len(_allow) > 0 {
					fromEndpoints: [for a in _allow {
						matchLabels: {
							"k8s:io.kubernetes.pod.namespace": a.namespace
							"k8s:app.kubernetes.io/name":      a.app
						}
					}]
					toPorts: [{ports: [{port: "\(_port)"}]}]
				},
			]
			if len(_in) > 0 {
				ingress: _in
			}
			egress: [
				_dns,
				for c in _calls {
					toEndpoints: [{
						matchLabels: {
							"k8s:io.kubernetes.pod.namespace": c.namespace
							"k8s:app.kubernetes.io/name":      c.app
						}
					}]
					toPorts: [{ports: [{port: "\(c.port)"}]}]
				},
				for f in in.network.egressFQDN {
					toFQDNs: [{matchName: f.host}]
					toPorts: [{ports: [{port: "\(f.port)"}]}]
				},
				if _hasDB {
					toEndpoints: [{matchLabels: _dbSelector}]
					toPorts:     [{ports: [{port: "5432"}]}]
				},
				if in.network.kubeAPI {
					toEntities: ["kube-apiserver"]
					toPorts:    [{ports: [{port: "443"}, {port: "6443"}]}]
				},
			]
		}
	}

	// The database pods are in the same namespace, which is default-deny.
	_databasePolicy: crd.#CiliumNetworkPolicy & {
		metadata: {name: "\(_svc)-db", labels: _labels}
		spec: {
			endpointSelector: matchLabels: _dbSelector
			ingress: [{
				fromEndpoints: [
					{matchLabels: _selector},
					{matchLabels: _dbSelector},
					{matchLabels: {"k8s:io.kubernetes.pod.namespace": #Cluster.cnpgNamespace}},
				]
				toPorts: [{ports: [{port: "5432"}, {port: "8000"}]}]
			}]
			egress: [
				_dns,
				{
					toEndpoints: [{matchLabels: _dbSelector}]
					toPorts:     [{ports: [{port: "5432"}, {port: "8000"}]}]
				},
				{
					toEntities: ["kube-apiserver"]
					toPorts:    [{ports: [{port: "443"}, {port: "6443"}]}]
				},
			]
		}
	}

	_objects: [
		_serviceAccount,
		if _hasSecrets {_secretProviderClass},
		if _hasDB {_database},
		if _hasDB {_databasePolicy},
		_service,
		_deployment,
		if _spec.pdb {_pdb},
		if in.public {_route},
		_networkPolicy,
	]
	_manifestsYAML: yaml.MarshalStream(_objects)
}

// Cluster-side names the render depends on (meta/delivery.md, "Cluster-side
// names the app render depends on").
#Cluster: {
	gatewayNamespace: "envoy-gateway-system"
	gatewayListener:  "https"
	openbao:          "https://openbao.openbao-system.svc:8200"
	openbaoMount:     "kubernetes"
	openbaoKV:        "kv"
	cnpgNamespace:    "cnpg-system"
	// ClusterImageCatalog of PostgreSQL images and the major version apps run.
	postgresCatalog: "postgresql"
	postgresMajor:   18
	// user and group of the container (distroless nonroot).
	uid: 65532
}
