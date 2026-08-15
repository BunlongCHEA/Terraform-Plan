# argo_dockerapp/

Deploys apps onto an existing K3s cluster (built in the root project's `digitalocean/`, `gke/`, or `raspberrypi/` folder) via `kubectl apply` + ArgoCD force-sync:

- **Elasticsearch + Kibana** — centralized logging UI (runs on one host, e.g. `desktop`)
- **Fluent Bit** — log shipper, runs on every server, forwards to Elasticsearch
- **RabbitMQ** — message queue

```
argo_dockerapp/
├── deploy.sh                <- run this
├── deploy.env.example        <- copy to deploy.env and fill in
├── get_kubeconfig.sh         <- run ON each remote k3s server
├── decode_kubeconfig.sh      <- run on your LOCAL machine
├── connect_k3s.sh             <- optional: opens all tunnels + tests at once
├── elk-fluentbit/
├── rabbitmq/
└── argocd/
```

---

## 1. Pre-Requirements — Install on Ubuntu or RedHat

This runs from your **local machine** (laptop/PC), not on the k3s server itself — unless you're running it directly on a k3s node, in which case skip straight to Section 3.

### Ubuntu / Debian
```bash
sudo apt update
sudo apt install -y openssh-client kubectl gettext-base netcat-openbsd
```

### RedHat / CentOS / Rocky / AlmaLinux
```bash
sudo yum install -y openssh-clients gettext nmap-ncat

# kubectl (no default yum package — install via the official repo)
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF
sudo yum install -y kubectl
```

**What each package is for:**
| Package | Used for |
|---|---|
| `openssh-client(s)` | SSH tunnels to reach each k3s server |
| `kubectl` | Talking to the cluster(s) |
| `gettext-base` / `gettext` (`envsubst`) | `deploy.sh` templates ArgoCD manifests with it |
| `netcat-openbsd` / `nmap-ncat` (`nc`) | `deploy.sh` checks if a tunnel port is already open |

Verify:
```bash
ssh -V
kubectl version --client
envsubst --version
nc -h
```

---

## 2. Test Connection, then Configure `deploy.env`

### Step 1 — Get each server's kubeconfig

**On each remote k3s server**, extract and base64-encode its kubeconfig:
```bash
cd argo_dockerapp
chmod +x get_kubeconfig.sh
./get_kubeconfig.sh
```
Copy the printed base64 output (or `scp` the saved file to your local machine).

**On your local machine**, decode it — repeat once per server, using a short name (`pi`, `desktop`, etc.):
```bash
chmod +x decode_kubeconfig.sh
./decode_kubeconfig.sh pi
./decode_kubeconfig.sh desktop
```
Paste the base64 when prompted, then `Ctrl+D`. Each is saved to `~/.kube/KUBECONFIG_<name>`.

### Step 2 — Set up SSH access to each server

Make sure each server has a working alias in `~/.ssh/config`, e.g.:
```
Host pi5
  HostName pi5-1.example.com
  User pi-admin
  ProxyCommand cloudflared access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519

Host desk
  HostName 192.168.1.50
  User desk-admin
  IdentityFile ~/.ssh/id_ed25519
```

### Step 3 — Test connectivity

**Via SSH directly:**
```bash
ssh pi5
ssh desk
```

**Via Ansible ping** (if this machine also has the root project's inventory available):
```bash
ansible -i ../raspberrypi/output/inventory.ini os_servers -m ping
```

**Via kubectl through a tunnel** (manual, one server at a time):
```bash
ssh -f -N -L 6443:127.0.0.1:6443 pi5
KUBECONFIG=~/.kube/KUBECONFIG_pi kubectl cluster-info
```

Or test everything at once with the helper script:
```bash
chmod +x connect_k3s.sh
./connect_k3s.sh
```

### Step 4 — Rename and configure `deploy.env`

```bash
cp deploy.env.example deploy.env
```

Edit `deploy.env` and fill in, per server:
```bash
K3S_SERVER_NAMES=(pi desktop)

PI_SSH_HOST="pi5"                        # matches ~/.ssh/config alias
PI_LOCAL_PORT=6443                       # local tunnel port for this server
PI_KUBECONFIG="$HOME/.kube/KUBECONFIG_pi"
PI_ARGOCD_DEST="https://<pi-ip>:6443"    # as seen from the ArgoCD host

DESKTOP_SSH_HOST="desk"
DESKTOP_LOCAL_PORT=6444                  # MUST differ from pi's local port
DESKTOP_KUBECONFIG="$HOME/.kube/KUBECONFIG_desktop"
DESKTOP_ARGOCD_DEST="https://<desktop-ip>:6443"

ES_HOST=<desktop-lan-ip>                 # where Elasticsearch/Kibana runs
ES_PORT=30920
ES_HOST_SERVER_NAME=desktop
ARGOCD_HOST_SERVER_NAME=pi               # which server ArgoCD itself is installed on
```

**Important:** each `<NAME>_LOCAL_PORT` must be a *different* number — that's the local port used only on your machine to reach that server's tunnel, and reusing one across two servers causes a TLS certificate mismatch error (wrong server answers your kubectl call). Adding a third server later just means adding four more `<NAME>_*` lines here — `deploy.sh` and `connect_k3s.sh` pick it up automatically.

---

## 3. Running `./deploy.sh`

```bash
chmod +x deploy.sh
```

**Interactive menu:**
```bash
./deploy.sh
```

**Or run a specific step directly:**
```bash
./deploy.sh test              # connectivity check only — verifies every server in deploy.env, deploys nothing
./deploy.sh es-kibana         # Elasticsearch + Kibana (on ES_HOST_SERVER_NAME)
./deploy.sh fluentbit-single  # Fluent Bit on this one server only
./deploy.sh fluentbit-multi   # Fluent Bit rolled out to every server in K3S_SERVER_NAMES via ArgoCD
./deploy.sh rabbitmq          # RabbitMQ
./deploy.sh all               # everything above, in order
```

`deploy.sh` always runs the connectivity check first — same idea as the `before_script` step in this repo's `.gitlab-ci.yml` files — and stops immediately if any server fails, before touching the cluster:
- If run **on a k3s node itself**, it auto-uses `/etc/rancher/k3s/k3s.yaml` — the simplest way to run it, no tunnels needed.
- If run **from your local machine**, it opens/reuses an SSH tunnel per server (per `deploy.env`) and checks each one.

**Verify after deploying:**
```bash
kubectl get pods -n logging
kubectl get pods -n rabbitmq
kubectl get applications -n argocd
```