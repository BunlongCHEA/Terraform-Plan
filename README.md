# Terraform-Plan

Provision Kubernetes (K3s/Rancher) clusters across three targets — **DigitalOcean**, **GKE (Google Cloud)**, and **existing hosts** (e.g. Raspberry Pi 5) — using Terraform + Ansible, then deploy apps on top with ArgoCD.

Everything is driven from **one runner at the project root**: `./terraform_main.sh <target> <command>`.

```
Terraform-Plan/
├── terraform_main.sh   # single runner for every target
├── ansible-common/     # shared playbooks, ArgoCD + certificate templates, shared group_vars
├── digitalocean/       # creates Droplet(s) → inventory for Ansible
├── gke/                # creates GCE VM(s)  → inventory for Ansible
├── raspberrypi/        # existing host(s), no VM created — inventory only
├── connect_k3s.sh      # SSH tunnel + kubeconfig for local kubectl
└── argo_dockerapp/     # deploy apps (ELK, RabbitMQ) onto the cluster — see its own README
```

---

## 1. Pre-Requirements — Your Local Machine

Do this once on the machine you'll run `./terraform_main.sh` from (Linux or WSL).

> **Terraform version is pinned:** every target requires `>= 1.14.0, < 1.15.0`. A newer 1.15+ release will fail `terraform init`.

### Ubuntu / Debian

**Terraform**
```bash
sudo apt update && sudo apt install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
apt-cache madison terraform | grep 1.14          # list available 1.14.x versions
sudo apt install -y terraform=1.14.*             # install a 1.14.x release
sudo apt-mark hold terraform                     # stop apt upgrading it to 1.15
terraform --version
```

**Ansible**
```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes ppa:ansible/ansible
sudo apt update && sudo apt install -y ansible
ansible --version
```

### RedHat / CentOS / Rocky / AlmaLinux

**Terraform**
```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum --showduplicates list terraform | grep 1.14   # list available 1.14.x versions
sudo yum install -y terraform-1.14.*
terraform --version
```

**Ansible**
```bash
sudo yum install -y epel-release
sudo yum install -y ansible
ansible --version
```

### Required Ansible collection (all OSes)
```bash
ansible-galaxy collection install kubernetes.core
```

### Clone the project
```bash
git clone https://github.com/BunlongCHEA/Terraform-Plan.git
cd Terraform-Plan
chmod +x terraform_main.sh connect_k3s.sh
```

---

## 2. Pre-Requirements — Per Cloud / Target

Only complete the block for the target(s) you plan to use.

### 2.1 DigitalOcean (`digitalocean`)

| Requirement | Where to get it |
|---|---|
| DigitalOcean account with billing enabled | https://cloud.digitalocean.com |
| **Personal Access Token** — scope **Full Access** (Read + Write) | Control Panel → **API** → **Tokens** → **Generate New Token** |

Notes:
- **No SSH key setup needed.** On first `apply`, Terraform generates `~/.ssh/id_rsa_digitalocean` (+ `.pub`) and uploads the public key to your DO account under `ssh_key_name`. If the key files or the DO key name already exist, they are reused.
- Droplets log in as `root`.

### 2.2 Google Cloud — GCE VM (`gke`)

> The `gke` target creates a **Compute Engine VM** and installs K3s on it — it does *not* create a managed GKE cluster.

| Requirement | Where to get it |
|---|---|
| GCP project with billing enabled | Console → **Billing** |
| **Compute Engine API** enabled | Console → **APIs & Services** → **Library** → *Compute Engine API* → **Enable** |
| **Service Account** with the 3 roles below | Console → **IAM & Admin** → **Service Accounts** → **Create Service Account** |
| **JSON key** for that service account | Service account → **Keys** → **Add Key** → **Create new key** → **JSON** |

Required IAM roles on the service account:

| Role | ID |
|---|---|
| Compute Admin | `roles/compute.admin` |
| Compute Security Admin | `roles/compute.securityAdmin` |
| Service Account User | `roles/iam.serviceAccountUser` |

Or via `gcloud`:
```bash
PROJECT_ID=<your-gcp-project-id>
SA=terraform-sa

gcloud services enable compute.googleapis.com --project "$PROJECT_ID"
gcloud iam service-accounts create "$SA" --project "$PROJECT_ID"
for ROLE in roles/compute.admin roles/compute.securityAdmin roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${SA}@${PROJECT_ID}.iam.gserviceaccount.com" --role "$ROLE"
done
mkdir -p ~/.gcp && gcloud iam service-accounts keys create ~/.gcp/${PROJECT_ID}-key.json \
  --iam-account "${SA}@${PROJECT_ID}.iam.gserviceaccount.com"
chmod 600 ~/.gcp/${PROJECT_ID}-key.json
```

Notes:
- Terraform generates `~/.ssh/id_rsa_gke` (+ `.pub`) on first `apply` and injects it via VM metadata for `ssh_user` (default `ubuntu`).
- Terraform only opens **TCP 22** in the firewall (`<project_name>-allow-ssh`). Open 80/443/6443 yourself if you need them from the internet, or publish through Cloudflare Tunnel.

### 2.3 Existing Host / Raspberry Pi (`raspberrypi`)

No cloud account needed — Terraform creates **no VM** here, it only renders an Ansible inventory for machines you already own.

| Requirement | Detail |
|---|---|
| Host OS | Ubuntu/Debian or RHEL-family, with **Python 3** |
| SSH access from your machine | Usually through an alias in `~/.ssh/config` (Cloudflare Tunnel or LAN) |
| **Passwordless sudo** for the SSH user | Playbooks run with `become: true` and fail otherwise |
| `cloudflared` on your local machine | Only if your SSH alias uses `ProxyCommand cloudflared ...` |

**a) Add an SSH alias** in `~/.ssh/config` on your local machine:
```sshconfig
# Through Cloudflare Tunnel / Access
Host pi5-1
  HostName pi5-1.example.com
  User pi-admin
  ProxyCommand cloudflared access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519

# Or directly on the LAN
Host k8-1
  HostName k8-1.example.com
  User pi-admin
  ProxyCommand cloudflared access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519
```

**b) Copy your public key to the host** (one time):
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi5-1
```

**c) Enable passwordless sudo** — run *on the host*:
```bash
echo "pi-admin ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/pi-admin
sudo chmod 440 /etc/sudoers.d/pi-admin
sudo visudo -c        # must print "parsed OK"
```

### 2.4 Optional — Cloudflare API Token

Only needed for DNS-01 (Let's Encrypt) certificates. Cloudflare dashboard → **My Profile** → **API Tokens** → **Create Token**:

| Field | Value |
|---|---|
| Permissions | Zone – DNS – Edit |
| Permissions | Zone – Zone – Read |
| Zone Resources | Include – Specific zone – your domain |

---

## 3. Config Files — Before Creating the VM

Each target needs **two** config files. Both are git-ignored, so your secrets never get committed.

| File | Used by | Purpose |
|---|---|---|
| `<target>/terraform.tfvars` | Terraform | Credentials, region, VM size/count, host list |
| `<target>/group_vars/all.yml` *(or shared `ansible-common/group_vars/all.yml`)* | Ansible | Domains + email for Rancher, ArgoCD, Kibana |

### 3.1 DigitalOcean — `digitalocean/terraform.tfvars`
```bash
cp digitalocean/terraform.tfvars.example digitalocean/terraform.tfvars
```
```hcl
do_token      = "dop_v1_xxxxxxxxxxxxxxxxxxxxxxxx"   # token from section 2.1
region        = "sgp1"                # Singapore
droplet_os    = "ubuntu-24-04-x64"
droplet_size  = "s-1vcpu-2gb"         # 2 GB minimum for K3s + Rancher
droplet_count = 1                     # >1 for a multi-node cluster
ssh_key_name  = "terraform-ansible-key"   # name shown in DO → Settings → Security
ssh_path      = "~/.ssh"
project_name  = "ansible-lab"         # prefix for droplet names
```

### 3.2 Google Cloud — `gke/terraform.tfvars`
```bash
cp gke/terraform.tfvars.example gke/terraform.tfvars
```
Set **exactly one** auth option — setting both, or neither, fails at `plan`:
```hcl
# OPTION 1 — base64 of the JSON key:   base64 -w 0 < ~/.gcp/<project>-key.json
gke_service_account_b64 = ""

# OPTION 2 — path to the JSON key (recommended)
gke_credentials_file    = "/home/<you>/.gcp/<project>-key.json"

gcp_project_id = "<your-gcp-project-id>"
region         = "asia-southeast1"
zone           = "asia-southeast1-a"
vm_os          = "ubuntu-2404-lts-amd64"
vm_os_project  = "ubuntu-os-cloud"
machine_type   = "e2-medium"          # 2 vCPU / 4 GB
vm_count       = 1
ssh_key_name   = "terraform-ansible-key"
ssh_path       = "~/.ssh"
ssh_user       = "ubuntu"
project_name   = "ansible-lab"
```

### 3.3 Raspberry Pi / existing hosts — `raspberrypi/variable.tf` + `terraform.tfvars`

This target needs **both** files copied:
```bash
cp raspberrypi/variable.tf.example     raspberrypi/variable.tf
cp raspberrypi/terraform.tfvars.example raspberrypi/terraform.tfvars
```
Edit `raspberrypi/terraform.tfvars` — `ansible_host` must match a `Host` alias from section 2.3:
```hcl
project_name = "ansible-lab"

pi_hosts = [
  { name = "pi5-1", ansible_host = "pi5-1", ansible_user = "pi-admin" },
  { name = "k8-1",  ansible_host = "k8-1",  ansible_user = "pi-admin" },
  # first entry = Rancher server in single-node mode
]

ssh_config_path = "~/.ssh/config"

# Keep true when using Cloudflare Access browser login (default).
# Set false only if SSH already works non-interactively.
skip_ssh_check = true
```

### 3.4 Ansible values — `group_vars/all.yml` (all targets)

The runner looks for values in this order:
1. `<target>/group_vars/all.yml` — **per-target** (different domain per cluster)
2. `ansible-common/group_vars/all.yml` — **shared** fallback for every target

Create one of them:
```bash
# Per target (recommended)
mkdir -p raspberrypi/group_vars
cp ansible-common/group_vars/all.yml.example raspberrypi/group_vars/all.yml

# OR one shared file for every target
cp ansible-common/group_vars/all.yml.example ansible-common/group_vars/all.yml
```
```yaml
---
# cloudflare_api_token : "<token from section 2.4>"   # optional, DNS-01
# cloudflare_email     : "you@example.com"
rancher_domain : "rancher1.example.com"
admin_email    : "admin@example.com"     # Let's Encrypt notifications
argocd_domain  : "argocd.example.com"
kibana_domain  : "kibana.example.com"
log_shipper    : "alloy"                 # alloy | fluent-bit | none
```

> Copy from `ansible-common/group_vars/all.yml.example` even for DigitalOcean/GKE — the per-target examples lack `argocd_domain`, `kibana_domain` and `log_shipper`.

### 3.5 Config checklist

| Target | `terraform.tfvars` | `variable.tf` | `group_vars/all.yml` |
|---|---|---|---|
| digitalocean | ✅ | — (in repo) | ✅ per-target or shared |
| gke | ✅ | — (in repo) | ✅ per-target or shared |
| raspberrypi | ✅ | ✅ copy from `.example` | ✅ per-target or shared |

---

## 4. Test Connection

Run from the **project root**. `output/inventory.ini` exists only after `apply` (section 5, step 3).

### 4.1 Before `apply` — Raspberry Pi only
```bash
ssh pi5-1 'hostname && sudo -n true && echo "sudo OK"'
```
Must print the hostname and `sudo OK`. If you see `sudo: a password is required`, redo section 2.3 (c).

### 4.2 After `apply` — all targets
```bash
./terraform_main.sh <target> test
# same as: ansible -i <target>/output/inventory.ini os_servers -m ping
```
Healthy output:
```
pi5-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### 4.3 Plain SSH (for debugging)
```bash
./terraform_main.sh <target> output                         # shows the VM IPs
ssh -i ~/.ssh/id_rsa_digitalocean root@<droplet-ip>         # DigitalOcean
ssh -i ~/.ssh/id_rsa_gke ubuntu@<vm-external-ip>            # GCE VM
ssh pi5-1                                                   # Raspberry Pi
```

### 4.4 Common failures

| Error | Fix |
|---|---|
| `Permissions 0644 for '...id_rsa_...' are too open` / bad permissions | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_rsa_* && chmod 644 ~/.ssh/id_rsa_*.pub` |
| `Inventory not found: <target>/output/inventory.ini` | Run `./terraform_main.sh <target> apply` first |
| `UNREACHABLE` right after creating a VM | VM is still booting — wait 30–60 s and re-run `test` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` (re-created VM, same IP) | `ssh-keygen -R <ip>` |
| Cloudflare alias hangs / times out | Run `ssh pi5-1` once by hand to finish the browser login, then `test` again |
| `Missing sudo password` | Passwordless sudo not set — section 2.3 (c) |

---

## 5. Run `./terraform_main.sh`

### 5.1 Syntax
```bash
./terraform_main.sh <target> <command>
#   target : digitalocean | gke | raspberrypi
```
Always run from the **project root**. The script `cd`s into the target folder for Terraform and uses the shared playbooks in `ansible-common/`.

### 5.2 Create the VM (or the inventory) — step by step
```bash
./terraform_main.sh digitalocean init       # 1. create output/ + rancher/, terraform init -upgrade
./terraform_main.sh digitalocean plan       # 2. preview — nothing is changed
./terraform_main.sh digitalocean apply      # 3. create VM(s) (no prompt) + write output/inventory.ini
./terraform_main.sh digitalocean test       # 4. Ansible ping (section 4.2)
```
Replace `digitalocean` with `gke` or `raspberrypi`. For `raspberrypi`, `apply` creates nothing remote — it only renders the inventory.

> ⚠️ `apply` runs with `-auto-approve` — always run `plan` first on cloud targets, because it starts billing immediately.

### 5.3 Install apps with Ansible — step by step

Run in this order (each step needs the previous one):
```bash
./terraform_main.sh <target> ansible      # 1. Python3, pip, Ansible on the host(s)
./terraform_main.sh <target> rancher      # 2. K3s + Helm + cert-manager + Rancher (10–20 min)
./terraform_main.sh <target> argocd       # 3. ArgoCD
./terraform_main.sh <target> prometheus   # 4. Prometheus (kube-prometheus-stack via ArgoCD)
./terraform_main.sh <target> logging      # 5. Elasticsearch + Kibana + log shipper (via ArgoCD)
./terraform_main.sh <target> grafana      # 6. Grafana + Loki + Tempo + Alloy (via ArgoCD)
```
- `rancher` asks: **1)** single node (first host in inventory only) or **2)** multi-node (all hosts).
- Install `logging` **before** `grafana` so Alloy auto-detects Elasticsearch and ships logs to it.

Or pick from a menu:
```bash
./terraform_main.sh <target> install
```
```
1) Ansible        2) Rancher       3) ArgoCD
4) Monitoring ->  (Prometheus only / Grafana stack only / Both)
5) Logging        6) All of the above (correct order)   7) Skip
```

### 5.4 One-shot full workflow
```bash
./terraform_main.sh raspberrypi all
```
Runs: create dirs → `init` → `validate` → `plan` → asks **yes/no** → `apply` → `output` → waits 30 s → `test` → install menu.

### 5.5 All commands

| Command | What it does |
|---|---|
| `all` | Full workflow (5.4) |
| `init` | Create `output/`, `rancher/`; `terraform init -upgrade` |
| `validate` | `terraform validate` |
| `plan` | `terraform plan` — preview only |
| `apply` | `terraform apply -auto-approve` + show outputs |
| `output` | Show Terraform outputs (IPs, hostnames) |
| `test` | Ansible ping against `os_servers` |
| `ansible` | Install Python3 / pip / Ansible on hosts |
| `rancher` | Install K3s + Rancher (single or multi-node prompt) |
| `argocd` | Install ArgoCD |
| `prometheus` | Install Prometheus |
| `grafana` | Install Grafana + Loki + Tempo + Alloy |
| `logging` | Install Elasticsearch + Kibana + shipper |
| `install` | Interactive install menu |
| `uninstall` | Interactive uninstall menu (Monitoring / Logging / ArgoCD / Rancher & K3s / Everything) |
| `destroy` | Asks `yes`. DO/GKE: deletes the VMs. Raspberry Pi: removes generated local files only — **the physical host is never touched** |
| `help` | Show usage |

> To remove everything cleanly, run `uninstall` → **5) Everything** — it removes ArgoCD-managed apps before ArgoCD, then Rancher/K3s.

### 5.6 Verify the cluster

Open the SSH tunnel and kubeconfig for local `kubectl`:
```bash
./connect_k3s.sh
kubectl get nodes
kubectl get pods -A
kubectl top nodes
```

---