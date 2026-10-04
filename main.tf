locals {
  # Prefix formats like: tk-tf-17-dev or tk-tf-17-prod
  prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==========================================================
# 1. Custom IAM Task Role (Challenge 1)
# ==========================================================
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "custom_task_role" {
  name               = "${local.prefix}-custom-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name        = "${local.prefix}-custom-task-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "app_data_access" {
  name        = "${local.prefix}-app-data-policy"
  description = "Grant S3 and DynamoDB permissions to the Flask container in ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*/*",
          "arn:aws:s3:::*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "custom_task_role_attach" {
  role       = aws_iam_role.custom_task_role.name
  policy_arn = aws_iam_policy.app_data_access.arn
}

# ==========================================================
# 2. Security Group for ECS Task
# ==========================================================
resource "aws_security_group" "ecs_sg" {
  name        = "${local.prefix}-ecs-sg"
  description = "Allow inbound HTTP traffic to container for ${var.environment}"
  vpc_id      = var.vpc_id

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
    Name        = "${local.prefix}-ecs-sg"
    Environment = var.environment
  }
}

# ==========================================================
# 3. Private ECR Repository (Per Environment)
# ==========================================================
resource "aws_ecr_repository" "ecr" {
  name         = "${local.prefix}-ecr"
  force_delete = true

  tags = {
    Environment = var.environment
  }
}

# ==========================================================
# 4. ECS Module
# ==========================================================
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.5.0"

  cluster_name               = "${local.prefix}-ecs"
  cluster_capacity_providers = ["FARGATE"]

  services = {
    "${local.prefix}-service" = {
      cpu           = var.container_cpu
      memory        = var.container_memory
      desired_count = var.desired_count

      # Explicitly set the task definition family name:
      family = "${local.prefix}-${var.environment}-task"

      # Disable the module's default task role and pass the custom one (Challenge 1)
      create_tasks_iam_role = false
      tasks_iam_role_arn    = aws_iam_role.custom_task_role.arn

      container_definitions = {
        "${local.prefix}-container" = {
          essential = true
          image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.prefix}-ecr:latest"
          port_mappings = [
            {
              containerPort = 8080
              protocol      = "tcp"
            }
          ]
          environment = [
            {
              name  = "APP_ENV"
              value = var.environment
            }
          ]
        }
      }

      assign_public_ip                   = true
      deployment_minimum_healthy_percent = 100
      subnet_ids                         = var.subnet_ids
      security_group_ids                 = [aws_security_group.ecs_sg.id]
    }
  }
}

# ==========================================================
# 5. Outputs
# ==========================================================
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

output "container_name" {
  value = "${local.prefix}-container"
}