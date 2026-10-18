# Multi‑Region AWS EC2 Linux Deployment, with iPerf and Automatic Key Pair Management

![Terraform](https://img.shields.io/badge/Terraform-1.12+-5C4EE5?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2-orange?logo=amazon-aws&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)

## Overview

This project provides a idempotent way to deploy EC2 AWS Linux resources, with iPerf, across multiple AWS regions using Terraform. It automatically manages EC2 key pairs on a per-region basis, generating new keys as needed and storing private keys and fingerprints locally. 

## Features

- **Multi-region deployment** with isolated state and logs per region.
- **Automatic EC2 key pair management:** Generates new key pairs if missing, safely stores PEM and fingerprint.
- **macOS Bash 3.2 compatible** scripting.
- **SSO & standard AWS CLI** authentication support.
- **Pluggable Terraform CLI flags** and easy region selection.

---

## Prerequisites

| Tool         | Version    | Install (macOS)                             |
|--------------|------------|---------------------------------------------|
| Terraform    | 1.12+      | `brew install hashicorp/tap/terraform`      |
| AWS CLI v2   | 2.27+      | `brew install awscli`                       |
| jq           | 1.7+       | `brew install jq`                           |
| yq           | 4.45+      | `brew install yq`                           |

> **Note:**  
> Ensure your AWS CLI is configured for SSO or your preferred authentication.  
> 
> ```bash
> aws sso login
> export AWS_PROFILE=<your-sso-profile>
> ```
>
> Your profile name is defined by `aws configure sso` (see `$HOME/.aws/config`). Alternatively, set `aws_profile` in `config.yaml`; the `AWS_PROFILE` environment variable takes precedence. The same profile is used by the AWS CLI and Terraform.
> For more information, review the [AWS CLI Getting Started Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html)

---

## Configuration

Edit `config.yaml` to declare your regions and key pair name:

```yaml
# aws_profile: my-sso-profile      # Optional; AWS_PROFILE env var takes precedence
keypair_name: mycompany-key        # Logical name (can be anything, per project)
key_dir: "~/.ssh"                  # Directory to store PEM and public key files
regions:
  - us-east-1
  - eu-central-1
tf_extra_flags: ""                 # Optional extra Terraform CLI flags
```

## Usage

1. Deploy Infrastructure
```bash
./iperf-ctl.sh create      # Deploys to all regions in config.yaml
```

2. Show Outputs
```bash
./iperf-ctl.sh output      # Shows outputs for all configured regions
```

3. Destroy Infrastructure
```bash
./iperf-ctl.sh destroy     # Destroys resources in all regions
```

You can also specify regions directly:
```bash
./iperf-ctl.sh create us-east-1 eu-west-1
```

## Directory Structure
```
.
├── config.yaml           # Configuration (regions, keypair, directories)
├── iperf-ctl.sh             # Multi-region automation script
├── main.tf               # Terraform root module (uses var.key_name)
├── variables.tf          # All variables (including key_name)
├── README.md             # Project documentation
├── logs/                 # Per-region Terraform logs
└── infra-<region>/       # Per-region isolated state directory
```

## Key Pair Management
- For each region, iperf-ctl.sh checks for an existing EC2 key pair.
- If missing, it creates a new ED25519 key pair via AWS CLI and stores:
  - PEM: <key_dir>/<region>-<keypair>.pem
  - Public key: <key_dir>/<region>-<keypair>.pub
- On subsequent runs, only verification occurs (no overwrite).
- If the key exists on AWS, but you don't have a .pem locally, you need to delete the key on AWS and re-create it, or define a new name on config.yaml
- It generates an `ssh_config` file in the script directory to facilitate ssh access (`ssh -F ./ssh_config <region>`). `destroy` regenerates it for the remaining regions and deletes it when none are left.

## Cleaning Up

To destroy all resources:

```bash
./iperf-ctl.sh destroy
```

You can also remove all files under logs and the infra-* directories.

## Troubleshooting
* SSO Expired?
  Re-run aws sso login if you receive authentication errors.

* Key Pair Already Exists?
  If you used a different key pair before, delete it in AWS Console or use a new name in config.yaml.

* Provider Download Slow?
  All Terraform providers are cached in .plugin-cache for speed; ensure this directory is writable.

## License

This project is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Author
Andre Gustavo Albuquerque  
[GitHub](https://github.com/andregca)

> Feel free to fork, submit issues, or open pull requests!
