

//////////////////////////////////////////////////////[ EFS STORAGE MODULE ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for efs env
# # ---------------------------------------------------------------------------------------------------------------------#

locals {
  efs = {
    "EFS_SYSTEM_ID"        = module.efs.id
    "EFS_SYSTEM_DNS_NAME"  = module.efs.dns_name
    "EFS_SYSTEM_ARN"       = module.efs.arn
    "EFS_ACCESS_POINTS"    = jsonencode(module.efs.access_points)
    "EFS_MOUNT_TARGETS"    = jsonencode(module.efs.mount_targets)
  }
}

resource "aws_ssm_parameter" "efs" {
  for_each    = local.efs
  name        = "/${local.project}/${each.key}"
  description = "EFS parameter: ${each.key}"
  type        = "String"
  value       = each.value
  tags = {
    Service   = "efs"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create EFS storage and access points
# # ---------------------------------------------------------------------------------------------------------------------#
module "efs" {
  source         = "terraform-aws-modules/efs/aws"
  version        = "2.0.0"
  name           = "${local.project}-magento"
  creation_token = "${local.project}-magento-efs"
  encrypted      = true
  enable_backup_policy  = false
  mount_targets         = { for az, id in zipmap(module.vpc.azs, module.vpc.private_subnets) : az => { subnet_id = id } }
  security_group_vpc_id = module.vpc.vpc_id
  security_group_name   = "${local.project}-efs"
  security_group_description = "EFS security group for ${local.project}"
  security_group_ingress_rules  = {
    vpc = {
      description = "NFS ingress from VPC private subnets"
      ip_protocol = "tcp"
      from_port   = 2049
      to_port     = 2049
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  attach_policy = true
  policy_statements = {
    {
      sid     = "EFSAccess"
      actions = [
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientMount"
      ]
      principals = [
        {
          type        = "AWS"
          identifiers = [
            module.ecs_cluster.task_exec_iam_role_arn,
            aws_iam_role.codebuild.arn
         ]
        }
      ]
    }
  }
  access_points = { for name, config in local.env.efs : name => {
    name = name
    posix_user = {
      gid = config.gid
      uid = config.uid
    }
    root_directory = {
      path = "/${name}"
      creation_info = {
        owner_uid   = config.uid
        owner_gid   = config.gid
        permissions = config.permissions
      }
    }
  }}
}
