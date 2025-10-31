

//////////////////////////////////////////////////////[ EFS STORAGE MODULE ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for efs env
# # ---------------------------------------------------------------------------------------------------------------------#

locals {
  efs = merge([
    for efs_key, efs_output in module.efs : {
      "EFS_${upper(efs_key)}_ID"            = efs_output.id
      "EFS_${upper(efs_key)}_DNS_NAME"      = efs_output.dns_name
      "EFS_${upper(efs_key)}_ARN"           = efs_output.arn
      "EFS_${upper(efs_key)}_ACCESS_POINTS" = jsonencode(try(efs_output.access_points, null))
      "EFS_${upper(efs_key)}_MOUNT_TARGETS" = jsonencode(try(efs_output.mount_targets, null))
    }
  ]...)
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
  version        = "1.8.0"
  name           = "${local.project}-magento"
  creation_token = "${local.project}-magento-efs"
  encrypted      = true
  attach_policy  = true
  enable_backup_policy  = false
  mount_targets         = { for az, id in zipmap(module.vpc.azs, module.vpc.private_subnets) : az => { subnet_id = id } }
  security_group_vpc_id = module.vpc.vpc_id
  security_group_name   = "${local.project}-efs"
  security_group_rules  = {
    vpc = {
      description = "NFS ingress from VPC private subnets"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
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
