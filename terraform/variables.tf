variable "project_name" {
  description = "Project name prefix used in resource names"
  type        = string
  default     = "event-platform"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "api_shared_secret" {
  description = "Shared secret expected in x-api-key header"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    managed_by = "terraform"
    workload   = "user-events"
  }
}
