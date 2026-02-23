# AI Monitoring Demo — Terraform Infrastructure

The infrastructure is split into two independent Terraform configs:

| Config | Purpose | Run frequency |
|--------|---------|---------------|
| `network/` | VPC, subnet, internet gateway, route table | Once (shared) |
| `ec2/` | EC2 instance, security group, IAM, SSH key pair | Per person |

All state is stored in the S3 bucket `emeafet-terraform-tfstates`, keyed by owner email.

> **Note:** The network has already been deployed. Skip straight to [Deploy an EC2 Environment](#2-deploy-an-ec2-environment) unless you need to recreate the VPC.

## Prerequisites

- AWS CLI configured with credentials for `eu-west-2`
- Terraform >= 1.5
- A New Relic ingest license key

## 1. Deploy the Network (once)

```bash
cd network
```

**Configure backend** — copy the example and replace with your email:

```bash
cp backend.hcl.example backend.hcl
```

```hcl
# backend.hcl
bucket  = "emeafet-terraform-tfstates"
key     = "you@example.com/network/terraform.tfstate"
region  = "eu-west-2"
encrypt = true
```

**Configure variables** — copy the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

```hcl
# terraform.tfvars
owner = "you@example.com"
```

**Deploy:**

```bash
terraform init -backend-config=backend.hcl
terraform apply
```

Note the outputs — you'll need `vpc_id` and `subnet_id` for the EC2 config.

## 2. Deploy an EC2 Environment

```bash
cd ../ec2
```

**Configure backend** — use your email in the key path:

```bash
cp backend.hcl.example backend.hcl
```

```hcl
# backend.hcl
bucket  = "emeafet-terraform-tfstates"
key     = "you@example.com/default/terraform.tfstate"
region  = "eu-west-2"
encrypt = true
```

**Configure variables** — create a `terraform.tfvars`. If using the existing shared network, use these values directly:

```hcl
# terraform.tfvars
owner                 = "you@example.com"
vpc_id                = "vpc-0315c4fef02beda4e"
subnet_id             = "subnet-059b02b03be148254"
new_relic_license_key = "YOUR_LICENSE_KEY"
```

**Deploy:**

```bash
terraform init -backend-config=backend.hcl
terraform apply
```

After apply:
- SSH key is auto-generated at `keys/<owner_slug>.pem` (e.g. `keys/dpacheco.pem`)
- Use the `ssh_tunnel_command` output to access services via localhost

## 3. Access Services

All web ports are closed to the internet. Access is via SSH tunnel only.

Run the tunnel command from the Terraform output:

```bash
ssh -i keys/dpacheco.pem \
  -L 8501:localhost:8501 \
  -L 8089:localhost:8089 \
  -L 8001:localhost:8001 \
  -L 8002:localhost:8002 \
  -N ubuntu@<public-ip>
```

Then open in your browser:

| Service | URL |
|---------|-----|
| Flask UI | http://localhost:8501 |
| Locust | http://localhost:8089 |
| AI Agent API | http://localhost:8001 |
| MCP Server API | http://localhost:8002 |

## Multiple Environments

To run multiple EC2 instances under the same network, each person only needs their own owner email and backend HCL file.

**Create your backend config:**

```hcl
# backend.hcl
bucket  = "emeafet-terraform-tfstates"
key     = "you@example.com/default/terraform.tfstate"
region  = "eu-west-2"
encrypt = true
```

**Set your owner in `terraform.tfvars`:**

```hcl
owner = "you@example.com"
```

**Deploy:**

```bash
terraform init -backend-config=backend.hcl -reconfigure
terraform apply
```

Each person gets their own state file, key pair, and namespaced AWS resources.

## S3 State Layout

```
s3://emeafet-terraform-tfstates/
  user-a@example.com/
    network/terraform.tfstate
    default/terraform.tfstate
  user-b@example.com/
    network/terraform.tfstate
    default/terraform.tfstate
```

## Tear Down

Destroy EC2 first, then network:

```bash
# EC2
cd ec2
terraform init -backend-config=backend.hcl
terraform destroy

# Network (only after all EC2 environments are destroyed)
cd ../network
terraform init -backend-config=backend.hcl
terraform destroy
```
