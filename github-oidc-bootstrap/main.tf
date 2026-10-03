data "aws_caller_identity" "current" {}

# 1. Existing GitHub OIDC Provider in AWS
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ==========================================================
# ROLE 1: Infrastructure Pipeline Role (tf-coaching17-infra)
# ==========================================================
data "aws_iam_policy_document" "infra_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_username}*/${var.github_infra_repository_name}*:*"]
    }
  }
}

resource "aws_iam_role" "infra_deployer_role" {
  name               = "tk-tf-coaching17-infra-deployer-role"
  assume_role_policy = data.aws_iam_policy_document.infra_trust.json

  tags = {
    Name    = "tk-tf-coaching17-infra-deployer-role"
    Purpose = "CI/CD Role for Terraform Infrastructure Repo"
  }
}

resource "aws_iam_role_policy_attachment" "infra_backend_attach" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator",
    "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AWSWAFFullAccess",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess"
  ])

  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = each.value
  #role       = aws_iam_role.infra_deployer_role.name
  #policy_arn = aws_
}

# Custom Policy to supply missing Application Auto Scaling permissions
resource "aws_iam_policy" "app_autoscaling_policy" {
  name        = "tk-tf-coaching17-infra-autoscaling-policy"
  description = "Allows Terraform to manage ECS Application Auto Scaling targets and policies"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAppAutoScaling"
        Effect = "Allow"
        Action = [
          "application-autoscaling:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_autoscaling_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.app_autoscaling_policy.arn
}

# ==========================================================
# ROLE 2: Application Pipeline Role (coaching17-app)
# ==========================================================
data "aws_iam_policy_document" "app_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_username}*/${var.github_app_repository_name}*:*"]
    }
  }
}

resource "aws_iam_role" "app_deployer_role" {
  name               = "tk-tf-coaching17-app-deployer-role"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json

  tags = {
    Name    = "tk-tf-coaching17-app-deployer-role"
    Purpose = "CI/CD Role for Container App Deployment"
  }
}

# Attach ECR PowerUser (Build, tag, and push container images)[cite: 9]
resource "aws_iam_role_policy_attachment" "app_ecr_attach" {
  role       = aws_iam_role.app_deployer_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser" #[cite: 9]
}

# Scoped ECS Task Deployment Permissions[cite: 9]
resource "aws_iam_policy" "app_ecs_deploy_policy" {
  name        = "tk-tf-coaching17-app-ecs-deploy-policy"
  description = "Permissions for App CI/CD to deploy tasks to ECS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSDeploymentPermissions"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRoleForECSTasks"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_ecs_deploy_attach" {
  role       = aws_iam_role.app_deployer_role.name
  policy_arn = aws_iam_policy.app_ecs_deploy_policy.arn
}

# ==========================================================
# Variables & Outputs
# ==========================================================
variable "github_repository_username" {
  description = "GitHub repository username"
  type        = string
  default     = "peh3" #[cite: 9]
}

variable "github_app_repository_name" {
  description = "GitHub repository name for application"
  type        = string
  default     = "coaching17-app" #[cite: 9]
}

variable "github_infra_repository_name" {
  description = "GitHub repository name for Terraform infra"
  type        = string
  default     = "tf-coaching17-infra"
}

variable "tfstate_bucket_name" {
  description = "S3 bucket storing terraform state"
  type        = string
  default     = "sctp-tfstate-ce13" #[cite: 7]
}

output "infra_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the tf-coaching17-infra repo"
  value       = aws_iam_role.infra_deployer_role.arn
}

output "app_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the coaching17-app repo"
  value       = aws_iam_role.app_deployer_role.arn
}
