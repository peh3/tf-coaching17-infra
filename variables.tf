variable "aws_region" {
  description = "Target AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier"
  type        = string
  default     = "tk-tf-17"
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ECS tasks run"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ECS tasks"
  type        = list(string)
}

variable "container_cpu" {
  description = "CPU units allocated to the task (256, 512, 1024)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory allocated to the task in MB (512, 1024, 2048)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of replica tasks to run"
  type        = number
  default     = 1
}