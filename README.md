# Terraform-Plan

Provision Kubernetes (K3s/Rancher) clusters across three targets — **DigitalOcean**, **GKE**, and **existing hosts** (e.g. Raspberry Pi 5) — using Terraform + Ansible, then deploy apps on top with ArgoCD.

```
Terraform-Plan/
├── digitalocean/     # creates a Droplet, then installs K3s/Rancher via Ansible
├── gke/              # creates a GCE VM, then installs K3s/Rancher via Ansible
├── raspberrypi/      # existing host(s), no VM created — inventory only
└── argo_dockerapp/   # deploy apps (ELK, RabbitMQ) onto the cluster — see its own README
```

---

## 1. Pre-Requirements — Install Terraform & Ansible

Do this once per machine you'll run `./terraform_run.sh` from.

### Ubuntu / Debian

**Terraform**
```bash
sudo apt update && sudo apt install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y
terraform --version
```

**Ansible**
```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes ppa:ansible/ansible
sudo apt update
sudo apt install -y ansible
ansible --version
```

### RedHat / CentOS / Rocky / AlmaLinux

**Terraform**
```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum install -y terraform
terraform --version
```

**Ansible**
```bash
sudo yum install -y epel-release
sudo yum install -y ansible
ansible --version
```

### Required Ansible collection (all OSes)

The playbooks use the `kubernetes.core` collection — install it after Ansible is installed:
```bash
ansible-galaxy collection install kubernetes.core
```

### Optional — Cloudflare API Token

Only needed if you want DNS-managed TLS certificates. Create a token with:

| Field | Value |
|---|---|
| Permissions | Zone – DNS – Edit |
| Permissions | Zone – Zone – Read |
| Zone Resources | Include – Specific zone – your domain |

---

## 2. Cloud-Specific Pre-Requirements

Pick the folder matching where you want the cluster. Each needs its own credentials before running `./terraform_run.sh`.

### DigitalOcean (`./digitalocean`)

- A DigitalOcean **API token** with **Read + Write (Create/Delete)** permission.
- Copy the example vars file and fill in your token and settings:
  ```bash
  cd digitalocean
  cp terraform.tfvars.example terraform.tfvars
  # edit terraform.tfvars: set do_token, region, etc.
  ```

### GKE / Google Cloud (`./gke`)

- A GCP **Service Account** with these IAM roles:
  - `roles/compute.securityAdmin` — Compute Security Admin
  - `roles/compute.admin` — Compute Admin
  - `roles/iam.serviceAccountUser` — Service Account User
- Download the service account's JSON key and point Terraform at it:
  ```bash
  cd gke
  cp terraform.tfvars.example terraform.tfvars
  # edit terraform.tfvars: set project_id, credentials file path, region/zone, etc.
  ```

### Existing Host / Raspberry Pi (`./raspberrypi`)

No cloud account needed — this target manages a machine you already own. Instead:

- The host must be reachable over SSH, typically via an alias defined in `~/.ssh/config` (e.g. through a Cloudflare Tunnel):
  ```
  Host pi5-1-remote
    HostName pi5-1.example.com
    User pi
    ProxyCommand cloudflared access ssh --hostname %h
    IdentityFile ~/.ssh/id_ed25519
  ```
- Then define that alias in Terraform's variables:
  ```bash
  cd raspberrypi
  cp variable.tf.example variable.tf
  # edit variable.tf: set pi_hosts to your host's ansible_host alias
  ```

---

## 3. Test Connection First

Before running any installation, confirm the target machine is actually reachable. Do this from inside the relevant folder (`digitalocean/`, `gke/`, or `raspberrypi/`) **after** `terraform apply` has generated `output/inventory.ini`.

**Via Ansible ping (recommended — this is what `./terraform_run.sh test` runs):**
```bash
ansible -i output/inventory.ini os_servers -m ping
```
A healthy host replies:
```
pi5-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**Via plain SSH:**
```bash
ssh -i ~/.ssh/id_rsa_digitalocean root@<droplet-ip>       # DigitalOcean
ssh -i ~/.ssh/id_rsa_gke ubuntu@<vm-ip>                    # GKE
ssh pi5-1-remote                                           # Raspberry Pi (uses ~/.ssh/config alias)
```

If SSH fails with a permissions error on the private key, fix it:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa_digitalocean
chmod 644 ~/.ssh/id_rsa_digitalocean.pub
```

---

## 4. Running `./terraform_run.sh`

Run from inside the folder for your target (`digitalocean/`, `gke/`, or `raspberrypi/`):
```bash
cd digitalocean        # or gke, or raspberrypi
chmod +x terraform_run.sh
./terraform_run.sh
```

You'll see a menu. Each option, explained:

| # | Command | What it does |
|---|---|---|
| 1 | `all` | Runs the full flow end-to-end: init → apply → choose an install step. Easiest starting point. |
| 2 | `init` | `terraform init` — downloads providers, sets up the working directory. Run this first, once. |
| 3 | `plan` | `terraform plan` — shows what *would* change, without touching anything. |
| 4 | `apply` | `terraform apply` — creates the VM (DigitalOcean/GKE) or just renders `output/inventory.ini` (Raspberry Pi, since no VM is created there). |
| 5 | `ansible` | Installs Python3, pip, and Ansible itself onto the new/existing host. |
| 6 | `rancher` | Installs K3s + Helm + cert-manager + Rancher Server. Prompts for single-node vs multi-node. Takes 10–20 min. |
| 7 | `argocd` | Installs ArgoCD onto the cluster. |
| 8 | `prometheus` | Installs Prometheus + Grafana + Node Exporter for monitoring. |
| 9 | `test` | Runs the Ansible ping connectivity check (Section 3 above). |
| 10 | `output` | Shows Terraform's output values (IPs, hostnames, etc.). |
| 11 | `uninstall` | Menu to remove Rancher, ArgoCD, or Prometheus individually. |
| 12 | `destroy` | DigitalOcean/GKE: deletes the VM. Raspberry Pi: only removes generated local files — **your physical Pi is never touched.** |
| 0 | — | Exit |

**Typical first run, step by step:**
```bash
./terraform_run.sh init      # 1. set up Terraform
./terraform_run.sh plan      # 2. review what will be created
./terraform_run.sh apply     # 3. create the VM (or generate inventory, for Pi)
./terraform_run.sh test      # 4. confirm Ansible can reach it
./terraform_run.sh ansible   # 5. install Python/Ansible prerequisites on the host
./terraform_run.sh rancher   # 6. install K3s + Rancher
./terraform_run.sh argocd    # 7. install ArgoCD
```
Or just run `./terraform_run.sh all` and follow the prompts — it walks through the same steps interactively.

**Verify the cluster afterward:**
```bash
kubectl get pods -A
kubectl get nodes
kubectl top nodes
```

---

## 5. Next: Deploy Apps with `./argo_dockerapp/`

Once a cluster is up (Section 4 complete), go to `argo_dockerapp/` to deploy applications (Elasticsearch/Kibana logging, Fluent Bit, RabbitMQ) onto it via ArgoCD:

```bash
cd ../argo_dockerapp
```

See **[argo_dockerapp/README.md](./argo_dockerapp/README.md)** for full setup and usage.