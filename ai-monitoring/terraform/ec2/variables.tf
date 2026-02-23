variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-2"
}

variable "owner" {
  description = "Owner email address applied to all resources"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.owner))
    error_message = "Owner must be a valid email address."
  }
}

variable "vpc_id" {
  description = "VPC ID (from network Terraform output)"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID (from network Terraform output)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (must support NVIDIA GPU for Ollama)"
  type        = string
  default     = "g5.xlarge"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100
}

variable "new_relic_license_key" {
  description = "New Relic ingest license key"
  type        = string
  sensitive   = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "aim-demo"
}

variable "model_a_name" {
  description = "Ollama model A identifier"
  type        = string
  default     = "mistral:7b-instruct"
}

variable "model_b_name" {
  description = "Ollama model B identifier"
  type        = string
  default     = "ministral-3:8b-instruct-2512-q8_0"
}
