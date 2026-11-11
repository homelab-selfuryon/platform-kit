// Package crd holds minimal, closed schemas for the custom resources
// #App renders. They cover the fields platform-kit sets and nothing else,
// so a typo is an error. None of the CUE central registry modules
// (cue.dev/x/crd/...) exist for these groups, and the generated schemas of the
// full CRDs are large and slow to evaluate.
package crd

import metav1 "cue.dev/x/k8s.io/apimachinery/pkg/apis/meta/v1"

#ObjectMeta: metav1.#ObjectMeta

// ---------------------------------------------------------------- Cilium

#CiliumNetworkPolicy: {
	apiVersion: "cilium.io/v2"
	kind:       "CiliumNetworkPolicy"
	metadata:   #ObjectMeta
	spec: {
		endpointSelector: #Selector
		ingress?:         [...#IngressRule]
		egress?:          [...#EgressRule]
	}

	#Selector: matchLabels: [string]: string

	#Port: {
		port:     string
		protocol: *"TCP" | "UDP" | "ANY"
	}
	#PortRule: {
		ports: [...#Port]
		rules?: dns: [...{matchPattern?: string, matchName?: string}]
	}

	#IngressRule: {
		fromEndpoints: [...#Selector]
		toPorts?:      [...#PortRule]
	}
	#EgressRule: {
		toEndpoints?: [...#Selector]
		toEntities?:  [...("kube-apiserver" | "world" | "cluster" | "host")]
		toFQDNs?:     [...{matchName: string}]
		toPorts?:     [...#PortRule]
	}
}

// ----------------------------------------------------------- Gateway API

#HTTPRoute: {
	apiVersion: "gateway.networking.k8s.io/v1"
	kind:       "HTTPRoute"
	metadata:   #ObjectMeta
	spec: {
		parentRefs: [...{
			group:        *"gateway.networking.k8s.io" | string
			kind:         *"Gateway" | string
			name:         string
			namespace?:   string
			sectionName?: string
		}]
		hostnames: [...string]
		rules: [...{
			matches?: [...{path: {type: "PathPrefix" | "Exact", value: string}}]
			backendRefs: [...{
				name:    string
				port:    int
				weight?: int
			}]
		}]
	}
}

// --------------------------------------------------------- CloudNativePG

#CNPGCluster: {
	apiVersion: "postgresql.cnpg.io/v1"
	kind:       "Cluster"
	metadata:   #ObjectMeta
	spec: {
		instances: int & >=1
		storage: {
			size:          string
			storageClass?: string
		}
		resources?: {
			requests?: [string]: string
			limits?: [string]:   string
		}
		imageCatalogRef?: {
			apiGroup: "postgresql.cnpg.io"
			kind:     "ImageCatalog" | "ClusterImageCatalog"
			name:     string
			major:    int
		}
		enableSuperuserAccess?: bool
		bootstrap?: initdb?: {
			database?: string
			owner?:    string
		}
		enablePDB?: bool
	}
}

// ----------------------------------------------- Secrets Store CSI driver

#SecretProviderClass: {
	apiVersion: "secrets-store.csi.x-k8s.io/v1"
	kind:       "SecretProviderClass"
	metadata:   #ObjectMeta
	spec: {
		provider: string
		parameters: [string]: string
	}
}
