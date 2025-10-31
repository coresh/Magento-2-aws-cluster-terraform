


/////////////////////////////////////////////////////////[ SSM ROLE POLICY ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM role to execute automations and documents
# # ---------------------------------------------------------------------------------------------------------------------#
data "aws_iam_policy_document" "ssm_policy" {
  statement {
    effect    = "Allow"
    actions   = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
    ]
    resources = [aws_codebuild_project.this.arn]
  }
  statement {
    effect    = "Allow"
    actions   = [
      "sns:Publish",
    ]
    resources = [module.sns["devops"].topic_arn]
  }
  statement {
    effect    = "Allow"
    actions   = [
      "ssm:StartAutomationExecution",
      "ssm:GetAutomationExecution",
    ]
    resources = [aws_ssm_document.release.arn]
  }
  statement {
    effect    = "Allow"
    actions   = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.project}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = [
      "ec2:DescribeInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ssm_service_role" {
  name               = "${local.project}-SSMServiceRole"
  description        = "Provides SSM manage automations and trigger CodeBuild"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json
}

resource "aws_iam_policy" "ssm_policy" {
  name   = "${local.project}-SSMPolicy"
  policy = data.aws_iam_policy_document.ssm_policy.json
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ssm_service_role.name
  policy_arn = aws_iam_policy.ssm_policy.arn
}
