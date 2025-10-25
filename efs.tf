

//////////////////////////////////////////////////////[ EFS STORAGE MODULE ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for efs env
# # ---------------------------------------------------------------------------------------------------------------------#

locals {
  efs = merge([
    for key, efs in module.efs : {
      "${upper(key)}_EFS_ID"        = efs.id
      "${upper(key)}_EFS_DNS_NAME"  = efs.dns_name
      "${upper(key)}_EFS_ARN"       = efs.arn
      "${upper(key)}_EFS_ACCESS_POINTS" = jsonencode(try(module.efs[key].access_points, null))
      "${upper(key)}_EFS_MOUNT_TARGETS" = jsonencode(try(module.efs[key].mount_targets, null))
    }
  ])
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
  for_each       = local.env.efs
  name           = "${local.project}-${each.key}"
  creation_token = "${local.project}-${each.key}-efs"
  encrypted      = true
  attach_policy                             = true
  deny_nonsecure_transport_via_mount_target = false
  enable_backup_policy                      = false
  create_replication_configuration          = false
  bypass_policy_lockout_safety_check        = false
  policy_statements = [{
      sid     = "ElasticfilesystemClientMount"
      actions = ["elasticfilesystem:ClientMount"]
      principals = [{
          type        = "AWS"
          identifiers = [data.aws_caller_identity.current.arn]
        }]
    }]
  mount_targets  = { for az, id in zipmap(module.vpc.azs, module.vpc.private_subnets) : az => { subnet_id = id } }
  security_group_vpc_id      = module.vpc.vpc_id
  security_group_name        = "${local.project}-${each.key}"
  security_group_description = "${local.project} EFS security group"
  security_group_rules = {
    vpc = {
      description = "${local.project} NFS ingress from VPC private subnets"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
      }
  }
  access_points = {
    posix = {
      name = each.key
      posix_user = {
        gid  = each.value.gid
        uid  = each.value.uid
      }
    }
    root = {
      root_directory = {
        path = "/${each.key}"
        creation_info = {
           owner_uid   = each.value.uid
           owner_gid   = each.value.gid
           permissions = each.value.permissions
        }
      }
    }
  }
}
