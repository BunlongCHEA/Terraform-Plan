# Requiement
- Ansible
- Terraform
- kubernetes.core
- **(Optional)** Cloudflare API Token for DNS Certificate with permission below:

| Field | Value |
|---|---|
| `Permissions` | Zone - DNS - Edit |
| `Permissions` | Zone - Zone - Read |
| `Zone Resources` | Include - Specific zone - dns.site |

# STEP 1 -- Install Terraform
## On Window

Go to Terraform official webiste -- https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli

- Go -- **Manual Installation**
- On -- **Pre-compiled executable**, choose .zip file to get installation page
- Then choose window and download according to your OS -- in my case, I choose **AMD64**
- Add **terraform.exe** to Window **Environment Variables PATH**
- Verify installation

```bash
terraform version
```

```bash
terraform -help
```

## On Linux

**Update your system and install necessary packages**

Ensure your system is up-to-date and you have the required tools to manage repositories like 
- curl, 
- gnupg, 
- and software-properties-common 
```bash
sudo apt update && sudo apt install -y gnupg software-properties-common curl
```

**Add the HashiCorp GPG key**

Import the official HashiCorp GPG key to verify the package signature:
```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

**Add the official HashiCorp repository**

Add the HashiCorp Linux repository to your system's software sources:
```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

**Install Terraform**

Update your package list to include the new repository's package information, then install Terraform:
```bash
sudo apt update && sudo apt install terraform -y
```

**Verify the installation**

```bash
terraform --version
```
You should see an output similar to Terraform v1.X.X on linux_amd64 (the exact version will vary). 

# STEP 2 -- Terraform: Run to Create Droplet on Ubuntu

** Requirement:

Ensure to DigitalOcean API Token with Create/Delete Permission
- Rename terraform.tfvars.example => terraform.tfvars
- Copy and Fill in each values for terraform.tfvars like do_token, region, etc...
- Then run below to create Droplets

```bash
cd ./digitalocean
```

```bash
./terraform_run.sh
```

On Terminal:

- Choose Option **1** for run Entire Flow
![Terminal Terraform Run - Full Run Entire Flow](/images/terraform-1.png)

- Keep Write **yes** to keep installation for create Droplet & Run Ansible
- Then wait until success installation required library
![Terminal Terraform Run - Success Ansible Installation Library](/images/ansible-1.png)

Then verify create Droplet with Ansible or SSH command

```bash
cd ./digitalocean
ansible -i output/inventory.ini os_servers -m ping
```

Or SSH

```bash
ssh -i ~/.ssh/id_rsa_digitalocean root@139.59.229.28
```

# STEP 3 -- (Optional) Require to Remove & Change Permission to Private Key
## If Window

Using Windows GUI --
- Right-click on **id_rsa_digitalocean** file
- Select **Properties**
- Go to **Security** tab
- Click **Advanced**
- Click **Disable inheritance**
- Select **"Remove all inherited permissions from this object"**
- Click **Add** → **Select a principal**
- Type your **Windows username** and click **OK**
- Check **Full control** and click **OK**
- Remove any other users/groups listed (Authenticated Users, Users, etc.)
- Click **Apply** → **OK**

## If Ubuntu

You can use Ubunut or WLS Ubuntu to run this
```bash
mkdir -p ~/.ssh

# Copy keys to WSL home
cp /mnt/d/1-Git/Terraform-Plan/digitalocean/ssh_keys/id_rsa_digitalocean ~/.ssh/
cp /mnt/d/1-Git/Terraform-Plan/digitalocean/ssh_keys/id_rsa_digitalocean.pub ~/.ssh/

# Set correct permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa_digitalocean
chmod 644 ~/.ssh/id_rsa_digitalocean.pub

# Verify
ls -la ~/.ssh/

# Test SSH
ssh -i ~/.ssh/id_rsa_digitalocean root@174.138.21.129
```

# OTHER: Clean-Up Any Partial Resources (if needed)

In case the SSH key was created but the droplet failed, you may need to clean up:

```bash
# Check current state
terraform state list

# If you see the SSH key in state but want to start fresh:
terraform destroy -auto-approve

# Or just continue - Terraform should handle it
terraform apply
```

## Or Use -- ./terraform_run.sh -- to destroy by click Option **9** & write **yes**

**NOTE:** **terraform destroy -auto-approve** can what created & even delete Droplet from DigitalOcean as well, just like Rollback to Original state.
So in short, NO need to Login Official DigitalOcean Website, and Destroy

![SSH Fail - Bad Permissions](/images/ssh-fail__bad-permission.png)

## Verify Kubectl Command : How to Check Pod Logs

List all pod logs
```bash
kubectl get pods -A
```

Check pod logs
```bash
kubectl logs -n cattle-system rancher-84d4764864-2c99q
```
![Kubectl - Check Pod Logs](/images/kubectl-1.png)

Describe Pod for Events
```bash
kubectl describe pod -n cattle-system rancher-84d4764864-2c99q
```

Check Node Resources
```bash
kubectl top nodes
kubectl top pods -A
```
![Kubectl - Check Resource Consume By Pods](/images/kubectl-2.png)

## How to Check Certificate Validity

Delete certificate
```bash
# Delete certificate clusterissuer with name
kubectl delete clusterissuer letsencrypt-prod

# Delete existing certificate request
kubectl delete certificaterequest -n cattle-system --all

# Delete certificate
kubectl delete certificate -n cattle-system --all

# Restart cert-manager
kubectl rollout restart deployment/cert-manager -n cert-manager

# Restart Rancher to trigger new certificate request
kubectl rollout restart deployment/rancher -n cattle-system
```

Check Certificate Status
```bash
kubectl get certificate -n cattle-system
```
![Kubectl - Check Certificate Status Success Run](/images/kubectl-3.png)

- READY: True = Certificate issued successfully ✅
- READY: False = Still pending or failed ❌

Describe Certificate for Details
```bash
kubectl describe certificate -n cattle-system
```
![Kubectl - Describe Certificate Success Run with Traefik](/images/kubectl-4.png)

Check CertificateRequest
```bash
kubectl get certificaterequest -n cattle-system
```

Get Certificate All
```bash
kubectl get certificate -A
```
