#########################
# Variables
#########################
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "profile" {
  description = "AWS CLI profile; null uses AWS_PROFILE / default credential chain (iperf-ctl.sh exports AWS_PROFILE)"
  type        = string
  default     = null
}

variable "key_name" {
  description = "Existing (or auto‑created) AWS EC2 key‑pair name"
  type        = string
}

variable "vpc_name" {
  description = "Name tag for the VPC"
  type        = string
}

variable "instance_name_prefix" {
  description = "Prefix for resource names/tags"
  type        = string
  default     = "iperf"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "user_data_path" {
  description = "Path to cloud‑init (user data) file"
  type        = string
}

variable "cato_pop_cidrs" {
  description = "Cato POP CIDRs allowed inbound on all ports/protocols (maintained by update-cato-pop-cidrs.sh)"
  type        = list(string)

  validation {
    condition     = length(var.cato_pop_cidrs) > 0 && alltrue([for c in var.cato_pop_cidrs : can(cidrhost(c, 0))])
    error_message = "cato_pop_cidrs must be a non-empty list of valid IPv4 CIDRs. Run ./update-cato-pop-cidrs.sh."
  }
}

variable "test_cidrs" {
  description = "CIDRs the user tests from; allowed inbound on all ports/protocols"
  type        = list(string)

  validation {
    condition     = length(var.test_cidrs) > 0
    error_message = "test_cidrs must be specified: list at least one source CIDR (e.g. your public IP as x.x.x.x/32) under test_cidrs in config.yaml."
  }

  validation {
    condition     = alltrue([for c in var.test_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in test_cidrs must be a valid IPv4 CIDR (e.g. 203.0.113.10/32)."
  }
}
