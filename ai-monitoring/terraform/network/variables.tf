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

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "aim-demo"
}
