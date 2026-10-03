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
      values   = ["repo:${var.github_repository_username}/${var.github_infra_repository_name}:*"]
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

# S3 Remote State Backend Access Policy
resource "aws_iam_policy" "terraform_backend_policy" {
  name        = "tk-tf-coaching17-infra-backend-policy"
  description = "Permissions for Terraform GitHub Actions to access remote S3 state"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.tfstate_bucket_name}"
      },
      {
        Sid    = "S3StateObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.tfstate_bucket_name}/tk/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_backend_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.terraform_backend_policy.arn
}

# Permissions to create/manage ECR, ECS, Security Groups, and IAM roles
resource "aws_iam_policy" "infra_provisioning_policy" {
  name        = "tk-tf-coaching17-infra-provisioning-policy"
  description = "Permissions for Terraform to provision ECS, ECR, and Networking"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageInfraResources"
        Effect = "Allow"
        Action = [
          "ecr:*",
          "ecs:*",
          "ec2:Describe*",
          "ec2:*SecurityGroup*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_provisioning_attach" {
  role       = aws_iam_role.infra_deployer_role.name
  policy_arn = aws_iam_policy.infra_provisioning_policy.arn
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
      values   = ["repo:${var.github_repository_username}/${var.github_app_repository_name}:*"]
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
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"#[cite: 9]
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
  default     = "peh3"#[cite: 9]
}

variable "github_app_repository_name" {
  description = "GitHub repository name for application"
  type        = string
  default     = "coaching17-app"#[cite: 9]
}

variable "github_infra_repository_name" {
  description = "GitHub repository name for Terraform infra"
  type        = string
  default     = "tf-coaching17-infra"
}

variable "tfstate_bucket_name" {
  description = "S3 bucket storing terraform state"
  type        = string
  default     = "sctp-tfstate-ce13"#[cite: 7]
}

output "infra_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the tf-coaching17-infra repo"
  value       = aws_iam_role.infra_deployer_role.arn
}

output "app_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the coaching17-app repo"
  value       = aws_iam_role.app_deployer_role.arn
}