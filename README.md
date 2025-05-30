# Multi‑Region AWS EC2 Linux Deployment, with iPerf and Automatic Key Pair Management

![Terraform](https://img.shields.io/badge/Terraform-1.8+-5C4EE5?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2-orange?logo=amazon-aws&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Usage](#usage)
- [Directory Structure](#directory-structure)
- [Key Pair Management](#key-pair-management)
- [Cleaning Up](#cleaning-up)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Author](#author)

---

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
| Terraform    | 1.8+       | `brew install hashicorp/tap/terraform`      |
| AWS CLI v2   | 2.16+      | `brew install awscli`                       |
| jq           | 1.7+       | `brew install jq`                           |
| yq           | 4.x        | `brew install yq`                           |

> **Note:**  
> Ensure your AWS CLI is configured for SSO or your preferred authentication.  
> 
> ```bash
> aws sso login
> export AWS_PROFILE=<your-sso-profile>
> ```
>
> Your AWS_PROFILE is defined when you use the command "aws configured". You can also check $HOME/.aws/config

---

## Configuration

Edit `config.yaml` to declare your regions and key pair name:

```yaml
keypair_name: mycompany-key        # Logical name (can be anything, per project)
key_dir: keys                      # Directory to store PEM and fingerprint
regions:
  - us-east-1
  - eu-central-1
tf_extra_flags: ""                 # Optional extra Terraform CLI flags

## Usage

1. Deploy Infrastructure
```bash
./deploy.sh create      # Deploys to all regions in config.yaml
```

2. Show Outputs
```bash
./deploy.sh output      # Shows outputs for all configured regions
```

3. Destroy Infrastructure
```bash
./deploy.sh destroy     # Destroys resources in all regions
```

You can also specify regions directly:
```bash
./deploy.sh create us-east-1 eu-west-1
```

## Directory Structure
```
.
├── config.yaml           # Configuration (regions, keypair, directories)
├── deploy.sh             # Multi-region automation script
├── main.tf               # Terraform root module (uses var.key_name)
├── variables.tf          # All variables (including key_name)
├── README.md             # Project documentation
├── logs/                 # Per-region Terraform logs
└── infra-<region>/       # Per-region isolated state directory
```

## Key Pair Management
- For each region, deploy.sh checks for an existing EC2 key pair.
- If missing, it creates a new ED25519 key pair via AWS CLI and stores:
  - PEM: keys/<region>-<keypair>.pem
  - Fingerprint: keys/<region>-<keypair>.fingerprint
- On subsequent runs, only verification occurs (no overwrite).
- If the key exists on AWS, but you don't have a .pem locally, you need to delete the key on AWS and re-create it, or define a new name on config.yaml

## Cleaning Up

To destroy all resources:

```bash
./deploy.sh destroy
```

You can also remove all files under logs, ssh_config file and infra-* directories.

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
