variable "account_id" {
  description = "Your AWS Account ID"
  type        = string
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1" # <-- you can change this to your region
}

variable "project_name" {
  description = "Project name prefix for tagging"
  type        = string
  default     = "ECS PROJECT"
}
