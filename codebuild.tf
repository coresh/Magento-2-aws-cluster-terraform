


/////////////////////////////////////////////////////////[ CODEDEPLOY ]///////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeBuild role
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role" "codebuild" {
  name = "${local.project}-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  role = aws_iam_role.codebuild.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          module.s3["releases"].s3_bucket_arn,
          "${module.s3["releases"].s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = module.efs.arn
      }
    ]
  })
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeBuild project
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_codebuild_project" "this" {
  name          = "${local.project}-efs-deploy"
  description   = "Deploy releases from S3 to EFS for ${local.project}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "EFS_SYSTEM_ID"
      value = module.efs.id
    }
    environment_variable {
      name  = "PROJECT"
      value = local.project
    }
  }
  source {
    type      = "S3"
    location  = "${module.s3["releases"].s3_bucket_arn}/"
    buildspec = "buildspec.yml"
  }
  vpc_config {
    vpc_id = module.vpc.vpc_id
    subnets = module.vpc.private_subnets
    security_group_ids = [
      aws_security_group.codebuild.id
    ]
  }
  logs_config {
    cloudwatch_logs {
      group_name  = "codebuild"
      stream_name = "codebuild"
    }
    s3_logs {
      status   = "ENABLED"
      location = "${module.s3["logs"].backet_arn}/codebuild"
    }
  }
}

