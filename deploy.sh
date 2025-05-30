#!/usr/bin/env bash
###############################################################################
# deploy.sh – Terraform multi‑region driver (macOS /bin/bash 3.2 compatible)
#
# USAGE
#   ./deploy.sh create              # uses regions from config.yaml
#   ./deploy.sh destroy eu-west-1   # overrides regions
#   ./deploy.sh output              # show outputs only
#
# ENV
#   CONFIG_FILE    – alternate YAML config (default ./config.yaml)
#   AWS_PROFILE    – SSO / IAM profile (run `aws sso login` first!)
#   TF_LOG         – usual Terraform debug flags (optional)
###############################################################################
set -euo pipefail

#──────────────────────── helpers ────────────────────────────────────────────
die() { printf '❌  %s\n' "$*" >&2; exit 1; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
progress_filter() {
  grep --line-buffered -E '(^[[:space:]]*│)|(^Apply complete)|(^Destroy complete)|(^Plan:)|(^No changes)|(^Outputs:)'
}
log_file() { printf '%s/terraform_%s_%s.log' "${LOG_DIR}" "$1" "$(date +%Y%m%d_%H%M%S)"; }

#──────────────────────── configuration ──────────────────────────────────────
CFG_FILE="${CONFIG_FILE:-$(dirname "$0")/config.yaml}"
[ -f "${CFG_FILE}" ] || die "Config file not found: ${CFG_FILE}"

keypair_name=$(yq -r '.keypair_name' "${CFG_FILE}")
key_dir=$(yq -r '.key_dir' "${CFG_FILE}")
[ -n "${keypair_name}" ] || die "keypair_name missing in config.yaml"
[ -n "${key_dir}" ] || die "key_dir missing in config.yaml"

# Expand the path
eval key_dir="$key_dir"

if [ ! -d "$key_dir" ]; then
    mkdir -p "$key_dir"
fi

cfg_regions=($(yq -r '.regions[]' "${CFG_FILE}"))
extra_tf_flags=$(yq -r '.tf_extra_flags' "${CFG_FILE}")

#──────────────────────── cli parsing ────────────────────────────────────────
[ $# -ge 1 ] || die "Usage: $0 <create|destroy|output> [regions…]"
action="$1"; shift
case "${action}" in create|destroy|output) ;; *) die "Action must be create, destroy or output";; esac
regions=("${@:-${cfg_regions[@]}}")
[ ${#regions[@]} -ge 1 ] || die "No regions provided via CLI or config.yaml"
action_upper=$(upper "${action}")

#──────────────────────── constants ──────────────────────────────────────────
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${BASE_DIR}/logs"; mkdir -p "${LOG_DIR}"
export TF_PLUGIN_CACHE_DIR="${BASE_DIR}/.plugin-cache"; mkdir -p "${TF_PLUGIN_CACHE_DIR}"
TEMPLATE_FILES=("${BASE_DIR}"/*.tf "${BASE_DIR}"/*.tfvars)

#──────────────────────── get abs path ───────────────────────────────────
abspath() {
  if [[ -d "$1" ]]
  then
      pushd "$1" >/dev/null
      pwd
      popd >/dev/null
  elif [[ -e "$1" ]]
  then
      pushd "$(dirname "$1")" >/dev/null
      echo "$(pwd)/$(basename "$1")"
      popd >/dev/null
  else
      echo "$1" does not exist! >&2
      return 127
  fi
}

#──────────────────────── keypair handling ───────────────────────────────────
# Helper to generate public key from PEM
pem_to_pub() {
  local pem_file="$1"
  [ -f "$pem_file" ] || return 1
  ssh-keygen -y -f "$pem_file"
}

create_keypair() {
  local pem_file="$1"
  set -x
  aws ec2 create-key-pair --key-name "${keypair_name}" --key-type ed25519 \
       --region "${region}" --key-format pem --output text \
       --query 'KeyMaterial' > "${pem_file}"
  set +x
  chmod 600 "${pem_file}"  
}

ensure_keypair() {
  local region="$1"
  local local_pem="${key_dir}/${region}-${keypair_name}.pem"
  local fp_file="${key_dir}/${region}-${keypair_name}.pub"

  # Try to obtain AWS public key (empty string if not existing)
  local aws_pub
  aws_pub=$(aws ec2 describe-key-pairs \
    --key-names "${keypair_name}" --region "${region}" --include-public-key \
    --query 'KeyPairs[0].PublicKey' --output text 2>/dev/null || true)

  if [[ -z "${aws_pub}" || "${aws_pub}" == "None" ]]; then
    echo "🔑  Key pair \"${keypair_name}\" NOT found in ${region}. Creating…"
    create_keypair "${local_pem}"
    # Generate local public key file for convenience
    pem_to_pub "${local_pem}" > "${fp_file}"
    chmod 600 "${fp_file}"
    echo "    ✓ created, PEM saved to ${local_pem}"
    return
  fi

  echo "🔑  Key pair \"${keypair_name}\" exists in ${region}"

  # Check for local PEM file
  if [ -f "${local_pem}" ]; then
    # Generate public key from PEM and compare
    local local_pub
    local_pub="$(pem_to_pub ${local_pem}) ${keypair_name}"
    if [ "$local_pub" = "$aws_pub" ]; then
      echo "    ✓ Local PEM matches AWS key."
      # Optionally update .pub file
      echo "$local_pub" > "${fp_file}"
      chmod 600 "${fp_file}"
    else
      echo "❌  Local PEM does NOT match AWS key!"
      echo "    You may want to delete the key pair \"${keypair_name}\" in AWS and re-run the script."
      return 2
    fi
  else
    echo "❌  Local PEM (${local_pem}) does not exist."
    echo "    Delete the AWS key pair \"${keypair_name}\" in region ${region} so it can be recreated by this script."
    return 3
  fi
}

write_ssh_config() {
  local regions=("$@")
  local config_file="ssh_config"
  : > "$config_file"  # Truncate or create
  # write common options
    cat >> "$config_file" <<EOF
Host *
    User ec2-user
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF

  for region in "${regions[@]}"; do
    local workdir="${BASE_DIR}/infra-${region}"
    # Get public IP from terraform output
    local public_ip
    public_ip=$(cd "$workdir" && terraform output -json 2>/dev/null | jq -r '.instance_public_ip.value // empty')
    [ -n "$public_ip" ] || continue

    local pem_file="${key_dir}/${region}-${keypair_name}.pem"
    cat >> "$config_file" <<EOF
Host ${region}
    HostName $public_ip
    IdentityFile $pem_file

EOF
  done
  echo "📝  Wrote SSH config file: $config_file"
}

#──────────────────────── main loop ──────────────────────────────────────────
for region in "${regions[@]}"; do
  workdir="${BASE_DIR}/infra-${region}"
  mkdir -p "${workdir}"
  # Copy template files only if they changed to avoid unnecessary inits
  rsync -u "${TEMPLATE_FILES[@]}" "${workdir}/" >/dev/null
  logfile=$(log_file "${region}")

  pushd "${workdir}" >/dev/null

  # First‑time init (fast thanks to plugin cache)
  if [[ ! -d .terraform ]]; then
    echo "🛠  Terraform init (${region})"
    set +e
    terraform init -upgrade | tee -a "${logfile}" | progress_filter
    set -e
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
      echo "❌  Terraform init failed for ${region} - ⚠️ skipping."
      popd >/dev/null
      continue
    else
      echo "✅  Terraform init successful for ${region}."
    fi
  fi
  echo "🔸  ${action_upper} in ${region}"
  case "${action}" in
    create)
      ensure_keypair "${region}"
      rc=$?
      if [ $rc -ne 0 ]; then
        # error with key generation
        echo "❌  Error with key processing for for $region." 
        echo "    Destroy what has been created, delete the key from AWS and re-run the script"
        exit
      fi
      terraform apply -auto-approve -var="aws_region=${region}" \
        -var="key_name=${keypair_name}" ${extra_tf_flags} \
        | tee -a "${logfile}" | progress_filter
      ;;
    destroy)
      terraform destroy -auto-approve -var="aws_region=${region}" \
        -var="key_name=${keypair_name}" ${extra_tf_flags} \
        | tee -a "${logfile}" | progress_filter
      ;;
    output)
      : ;; # handled below
  esac

  printf '\n📦  Terraform outputs for %s:\n' "${region}"
  terraform output -json | jq -r 'to_entries[] | "• \(.key)=\(.value.value)"'
  echo
  popd >/dev/null
done

echo "🎉  ${action_upper} finished for regions: ${regions[*]}"

if [ "$action" = "create" ]; then
  write_ssh_config "${regions[@]}"
  echo "________________________"
  echo "🔑  Example SSH commands:"
  for region in "${regions[@]}"; do
    echo "  ssh -F ./ssh_config $region"
  done
fi