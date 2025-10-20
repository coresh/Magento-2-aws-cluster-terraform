


/////////////////////////////////////////////////////////[ CODEDEPLOY ]///////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeDeploy role
# # ---------------------------------------------------------------------------------------------------------------------#
data "aws_iam_policy_document" "codedeploy_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name        = "${local.project}-codedeploy-role"
  description = "Allows CodeDeploy to call AWS services on your behalf."
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume_role.json
  tags = {
    Name = "${local.project}-codedeploy-role"
  }
}

resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codedeploy.name
}

data "aws_iam_policy_document" "codedeploy" {
  statement {
    sid    = "AllowCodeDeployToASG"
    effect = "Allow"
    actions = [
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:PutLifecycleHook",
      "autoscaling:DeleteLifecycleHook",
      "autoscaling:RecordLifecycleActionHeartbeat"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codedeploy" {
  role   = aws_iam_role.codedeploy.name
  policy = data.aws_iam_policy_document.codedeploy.json
}
# # ---------------------------------------------------------------------------------------------------------------------#
# CodeDeploy Applications for backend ASG
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_codedeploy_app" "this" {
  for_each         = local.env.ec2
  name             = "${local.project}-${each.key}-codedeploy-app"
  compute_platform = "Server"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# CodeDeploy Deployment Groups for ASGs
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_codedeploy_deployment_group" "this" {
  for_each                 = local.env.ec2
  deployment_group_name    = "${local.project}-${each.key}-deployment-group"
  deployment_config_name   = "CodeDeployDefault.AllAtOnce"
  app_name                 = aws_codedeploy_app.this[each.key].name
  service_role_arn         = aws_iam_role.codedeploy.arn
  autoscaling_groups       = [module.autoscaling[each.key].autoscaling_group_name]
  termination_hook_enabled = true
  trigger_configuration {
    trigger_events     = ["DeploymentStart","DeploymentSuccess","DeploymentFailure"]
    trigger_name       = "${local.project}-${each.key}-deployment-notification"
    trigger_target_arn = module.sns["devops"].topic_arn
  }
}