#########################
# Variables
#########################
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "profile" {
  description = "AWS CLI SSO Profile"
  type        = string
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