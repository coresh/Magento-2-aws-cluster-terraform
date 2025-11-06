


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
  name          = "${local.project}-deploy-release"
  description   = "Deploy releases from S3 to EFS for ${local.project}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_LARGE"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "S3_RELEASE_BUCKET"
      value = module.s3["releases"].s3_bucket_id
    }
    environment_variable {
      name  = "RELEASE_FILE"
      value = ""
    }
    environment_variable {
      name  = "PROJECT"
      value = local.project
    }
  }
  file_system_locations {
    type        = "EFS"
    location    = "${module.efs.dns_name}:/"
    mount_point = "/mnt/efs"
    identifier  = "mount_release"
  }
  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec.yml")
  }
  vpc_config {
    vpc_id = module.vpc.vpc_id
    subnets = module.vpc.private_subnets
    security_group_ids = [
      module.codebuild_security_group.security_group_id
    ]
  }
  logs_config {
    cloudwatch_logs {
      group_name  = "${local.project}-codebuild-release"
      stream_name = "${local.project}-codebuild-release"
    }
    s3_logs {
      status   = "DISABLED"
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create CodeBuild security group
# # ---------------------------------------------------------------------------------------------------------------------#
module "codebuild_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "5.3.0"
  name        = "${local.project}-codebuild"
  description = "Security group for CodeBuild to access EFS and internet"
  vpc_id      = module.vpc.vpc_id
  ingress_with_cidr_blocks = []
  egress_with_source_security_group_id = [
    {
      rule                     = "nfs-tcp"
      source_security_group_id = module.efs.security_group_id
      description              = "Allow NFS access to EFS"
    }
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow HTTPS outbound to internet"
    },
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow HTTP outbound to internet"
    }
  ]
  tags = {
    Name = "${local.project}-codebuild"
  }
}









