locals {
  prefix = "tk-tf-17"

  vpc_id = "vpc-071dc429d54e64259"
  subnet_ids = [
    "subnet-07fe08d5909e677db", # sctp-vpc-ce13-public-us-east-1a
    "subnet-00b4c98869b996d86"  # sctp-vpc-ce13-public-us-east-1b
  ]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_security_group" "ecs_sg" {
  name        = "${local.prefix}-ecs-sg"
  description = "Allow inbound HTTP traffic to container"
  vpc_id      = local.vpc_id

  ingress {
    description = "Allow HTTP on port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}-ecs-sg"
  }
}

resource "aws_ecr_repository" "ecr" {
  name         = "${local.prefix}-ecr"
  force_delete = true
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.5.0"

  cluster_name = "${local.prefix}-ecs"
  cluster_capacity_providers = ["FARGATE"]

  services = {
    #YOUR-TASKDEFINITION-NAME = { #task definition and service name -> #Change
    "${local.prefix}-service" = {
      cpu    = 512
      memory = 1024
      container_definitions = {
        #YOUR-CONTAINER-NAME = { #container name -> Change
        "${local.prefix}-container" = {
          essential = true
          image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.prefix}-ecr:latest"
          port_mappings = [
            {
              containerPort = 8080
              protocol      = "tcp"
            }
          ]
        }
      }
      assign_public_ip                   = true
      deployment_minimum_healthy_percent = 100
      #subnet_ids                   = [] #List of subnet IDs to use for your tasks
      #security_group_ids           = [] #Create a SG resource and pass it here
      subnet_ids                         = local.subnet_ids
      security_group_ids                 = [aws_security_group.ecs_sg.id]
    }
  }
}

# Outputs for your GitHub Actions environment variables
output "ecr_repository_name" {
  value = aws_ecr_repository.ecr.name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = "${local.prefix}-service"
}

output "task_definition_family" {
  value = "${local.prefix}-service"
}