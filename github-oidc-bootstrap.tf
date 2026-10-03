data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
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
      values   = ["repo:${var.github_repository_username}*/${var.github_repository_name}*:*"]
    }
  }
}

resource "aws_iam_role" "github_oidc" {
  name               = var.github_oidc_role_name
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryPowerUser" {
  role       = aws_iam_role.github_oidc.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

variable "github_repository_username" {
  description = "GitHub repository username"
  type        = string
  default     = "peh3"
}

variable "github_repository_name" {
  description = "GitHub repository name"
  type        = string
  default     = "coaching17-app"
}

variable "github_oidc_role_name" {
  description = "Name of the GitHub OIDC role"
  type        = string
  default     = "tk-coaching17-github-oidc-role"
}

output "github_oidc_role_arn" {
  value = aws_iam_role.github_oidc.arn
}

resource "aws_iam_policy" "ecs_deploy_policy" {
  name        = "tk-coaching17-ecs-deploy-policy"
  description = "Permissions for GitHub Actions to deploy to ECS"

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
        Resource = "arn:aws:iam::255945442255:role/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_oidc_ecs_deploy" {
  role       = aws_iam_role.github_oidc.name
  policy_arn = aws_iam_policy.ecs_deploy_policy.arn
}