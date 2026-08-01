# argo_dockerapp/

Sibling directory to `raspberrypi/` in the repo root. Adds centralized pod
logging (Elasticsearch + Kibana + Fluent Bit) and RabbitMQ, deployed to the
same K3s/Raspberry Pi cluster via kubectl + ArgoCD, following the conventions
already used by `raspberrypi/terraform_run.sh` and the KYC `.gitlab-ci.yml`
files (before_script connectivity check, then apply + force-sync).

```
argo_dockerapp/
├── deploy.sh                          <- run this
├── elk-fluentbit/
│   ├── dockerfiles/
│   │   ├── elasticsearch/  Dockerfile + elasticsearch.yml
│   │   └── kibana/         Dockerfile + kibana.yml
│   └── k8s/
│       ├── 00-namespace.yaml
│       ├── 10-elasticsearch.yaml      (StatefulSet + headless Service, 10Gi PVC)
│       ├── 20-kibana.yaml             (Deployment + Service + Ingress)
│       ├── 30-fluent-bit-rbac.yaml    (ClusterRole — all namespaces, incl. future ones)
│       ├── 31-fluent-bit-configmap.yaml
│       └── 32-fluent-bit-daemonset.yaml
├── rabbitmq/
│   ├── dockerfile/          Dockerfile, enabled_plugins, rabbitmq.conf
│   └── k8s/
│       ├── 00-namespace-and-secret.yaml   (⚠ change RABBITMQ_DEFAULT_PASS)
│       └── 10-rabbitmq.yaml               (Deployment + PVC + Service + Ingress)
└── argocd/
    ├── logging-application.yaml    (path: argo_dockerapp/elk-fluentbit/k8s)
    └── rabbitmq-application.yaml   (path: argo_dockerapp/rabbitmq/k8s)
```

## deploy.sh

Menu-driven, same style as `raspberrypi/terraform_run.sh`. It always
verifies cluster connectivity first — same idea as the `before_script` block
in the repo's `.gitlab-ci.yml` files:

- If `KUBE_CONFIG_BASE64` is set (CI), it decodes it to `~/.kube/config`,
  same as the deploy stage in `.gitlab-ci.yml`.
- Else if run **directly on the Raspberry Pi/K3s node**, it uses
  `/etc/rancher/k3s/k3s.yaml` automatically — this is the recommended way to
  run it, per your note, so you don't need CI at all for this.
- Either way it runs `kubectl cluster-info` + `kubectl get nodes` and stops
  immediately if that fails, before touching anything.

```bash
cd argo_dockerapp
chmod +x deploy.sh   # already executable in this zip, but just in case

# Interactive menu
./deploy.sh

# Or non-interactive:
./deploy.sh test            # connectivity check only, deploys nothing
./deploy.sh logging         # Elasticsearch + Kibana + Fluent Bit
./deploy.sh logging-only    # Elasticsearch + Kibana, Fluent Bit skipped for now
./deploy.sh rabbitmq        # RabbitMQ only
./deploy.sh all             # everything
```

`logging-only` exists because you said Fluent Bit is "for now" optional —
run `./deploy.sh logging` later to layer it on top without redeploying
Elasticsearch/Kibana.

Each deploy step does `kubectl apply -f` on the manifests, then applies the
matching ArgoCD `Application` and force-syncs it — same pattern as the
`deploy` stage in your existing `.gitlab-ci.yml` files.

## Before running

1. Build & push the three custom images, update the `image:` lines:
   ```bash
   docker build -t <registry>/kyc-elasticsearch:latest elk-fluentbit/dockerfiles/elasticsearch
   docker build -t <registry>/kyc-kibana:latest        elk-fluentbit/dockerfiles/kibana
   docker build -t <registry>/kyc-rabbitmq:latest       rabbitmq/dockerfile
   ```
2. Set a real `RABBITMQ_DEFAULT_PASS` in `rabbitmq/k8s/00-namespace-and-secret.yaml`
   (or better, `kubectl create secret` it directly, same as the
   `gitlab-registry` pull secret pattern already used elsewhere in the repo,
   instead of committing it).
3. Confirm `repoURL` in both `argocd/*-application.yaml` files — currently
   assumed to be the same repo as the KYC app (`Python-Blockchain-KYC`).
4. Point `kibana.bunlong.uk` / `rabbitmq.bunlong.uk` DNS at the same IP as
   `prometheus.bunlong.uk` / `grafana.bunlong.uk`.
