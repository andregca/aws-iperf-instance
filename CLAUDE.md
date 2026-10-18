# CLAUDE.md

## Purpose

Deploys one Amazon Linux 2023 EC2 instance running an `iperf3` server in each AWS region the user selects, for network throughput/latency testing between regions. Regions are chosen in `config.yaml` or as CLI arguments to `iperf-ctl.sh`. Each region is an independent Terraform deployment.

## Layout

| File | Role |
|---|---|
| `iperf-ctl.sh` | Driver (bash 3.2 compatible, macOS). Actions: `create`, `destroy`, `output`. Loops over regions. |
| `config.yaml` | `keypair_name`, `key_dir`, default `regions` list, `tf_extra_flags`. Read with `yq`. |
| `main.tf` | Single-region template: VPC `10.0.0.0/16`, one public subnet (first AZ), IGW, route table, security groups (see Inbound access), EC2 instance, outputs `instance_public_ip` / `instance_public_dns`. |
| `variables.tf` | `aws_region`, `profile`, `key_name`, `vpc_name`, `instance_name_prefix`, `instance_type` (default `t2.micro`), `user_data_path`. |
| `terraform.tfvars` | Shared defaults (profile, names, instance type, `user_data_path = "../aws-cloudinit-iperf3.sh"`). |
| `update-cato-pop-cidrs.sh` | Downloads the Cato POP feed, keeps IPv4, consolidates CIDRs (55 from 332 prefixes at last run) and rewrites the `BEGIN/END cato_pop_cidrs` block in `terraform.tfvars`. Re-run periodically. |
| `update-test-cidr.sh` | First checks you are not connected to Cato (DNS `10.254.254.1` answers only through the tunnel; pauses and asks the user to disconnect, aborts when non-interactive), then detects the current public IPv4 (`https://ifconfig.me`) and writes `<ip>/32` into `test_cidrs` in `config.yaml`. Only replaces the entry tagged `# auto-detected` (manual entries kept; the 203.0.113.0/24 placeholder is removed). Re-run `create` afterwards to update the SG. |
| `aws-cloudinit-iperf3.sh` | EC2 user data: installs iperf3, creates a systemd `iperf3.service` (`iperf3 -s`, user `nobody`, logs to `/var/log/iperf3-server.log`), logrotate config. |
| `ssh_config` | Generated in the script directory by `iperf-ctl.sh create`; rebuilt after `destroy` from regions that still have instances and removed when none remain. Git-ignored. |
| `infra-<region>/`, `logs/`, `.plugin-cache/` | Generated, git-ignored. Never edit by hand. |

## How `iperf-ctl.sh` works

1. Reads `config.yaml`; regions come from CLI args (`./iperf-ctl.sh create us-east-1 eu-west-1`) or fall back to `config.yaml`.
2. For each region: creates `infra-<region>/`, rsyncs `*.tf` and `*.tfvars` into it (`rsync -u`), runs `terraform init` once, then `terraform apply|destroy -auto-approve -var aws_region=... -var key_name=...`.
3. `create` first runs `ensure_keypair`: checks for EC2 key pair `keypair_name` in the region and creates an ed25519 key via the AWS CLI if missing. PEM is saved to `<key_dir>/<region>-<keypair_name>.pem` and the public key to `.pub`. If the key exists in AWS but the local PEM is missing or mismatched, it fails and the user must delete the AWS key pair.
4. After `create`, `write_ssh_config` writes `ssh_config` with a `Host <region>` entry per instance (user `ec2-user`). Connect with `ssh -F ./ssh_config <region>`. After `destroy` it is regenerated for the remaining regions, or deleted if none are left.
5. State is local, one directory per region, so deleting `infra-<region>/` before `destroy` orphans the resources.

AWS profile: `AWS_PROFILE` env wins, else optional `aws_profile` in `config.yaml`; `iperf-ctl.sh` exports it so the AWS CLI and Terraform use the same one (`var.profile` defaults to null).

Requires `terraform`, `aws` CLI v2, `jq`, `yq` (mikefarah v4), `rsync`. Run `aws sso login` first; `create`/`destroy` verify this with `aws sts get-caller-identity` and exit early if not authenticated (`output` skips the check).

## Adding or changing things

- **Regions:** edit `regions:` in `config.yaml` (commented entries are inactive) or pass them on the command line. Regions must be enabled in the AWS account. No Terraform change is needed.
- **Instance size or names:** `terraform.tfvars`. Note `rsync -u` only copies newer files, so touch the file if a change is not picked up, and re-run `create`.
- **Instance setup:** `aws-cloudinit-iperf3.sh`. Changing it forces instance replacement on the next apply. The path is relative to `infra-<region>/`, hence `../`.
- **Inbound access:** outbound is allow-all; inbound is allow-all-ports/protocols only from two source sets, each in its own SG on the instance ENI. `cato_pop` SG(s): `cato_pop_cidrs` from `terraform.tfvars`, chunked at 60 rules per SG (AWS default quota), max 4 chunks (5 SGs per ENI default, the 5th is the test SG). `test` SG: `test_cidrs` from `config.yaml` (required; `create` exits with an error if empty, and `variables.tf` validates it too) plus the allow-all egress rule. Nothing is open to `0.0.0.0/0` inbound, so SSH works only from those sources. iperf3 listens on 5201.

## Verifying changes

There are no tests. Use `terraform fmt -check` and `terraform validate` (inside an `infra-<region>/` dir after init), `bash -n iperf-ctl.sh`, and `shellcheck iperf-ctl.sh` if available. `./iperf-ctl.sh create|destroy` makes real, billable AWS changes with `-auto-approve`, so confirm with the user before running them.