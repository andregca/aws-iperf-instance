# ------------- terraform.tfvars-------------
# Adjust the values as needed.
# ---------------------------------------------------
aws_region          = "us-east-1"
profile             = "default"
vpc_name             = "iperf-vpc"
instance_name_prefix = "linux-iperf"
instance_type        = "t2.micro"
user_data_path       = "../aws-cloudinit-iperf3.sh"

# you can pass aws_region at runtime or via the shell script.
