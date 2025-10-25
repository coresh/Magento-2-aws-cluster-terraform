

/////////////////////////////////////////////////////[ ELASTICACHE MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "elasticache" {
  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for elasticache env
# # ---------------------------------------------------------------------------------------------------------------------#
locals {
  elasticache = {
    # Session Cluster
    ELASTICACHE_SESSION_CLUSTER_ARN              = try(module.elasticache["session"].arn, null)
    ELASTICACHE_SESSION_ENGINE_VERSION           = try(module.elasticache["session"].engine_version_actual, null)
    ELASTICACHE_SESSION_CLUSTER_ADDRESS          = try(module.elasticache["session"].cluster_address, null)
    ELASTICACHE_SESSION_CONFIGURATION_ENDPOINT   = try(module.elasticache["session"].configuration_endpoint, null)
    ELASTICACHE_CACHE_CLUSTER_ARN                = try(module.elasticache["cache"].arn, null)
    ELASTICACHE_CACHE_ENGINE_VERSION             = try(module.elasticache["cache"].engine_version_actual, null)
    ELASTICACHE_CACHE_CLUSTER_ADDRESS            = try(module.elasticache["cache"].cluster_address, null)
    ELASTICACHE_CACHE_CONFIGURATION_ENDPOINT     = try(module.elasticache["cache"].configuration_endpoint, null)
  }
}

resource "aws_ssm_parameter" "elasticache" {
  for_each    = local.elasticache
  name        = "/${local.project}/${each.key}"
  description = "ElastiCache parameter: ${each.key}"
  type        = "String"
  value       = each.value
  tags = {
    Service   = "elasticache"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Elasticache redis replication group
# # ---------------------------------------------------------------------------------------------------------------------#
module "elasticache" {
  create                     = local.env.elasticache.create
  source                     = "terraform-aws-modules/elasticache/aws"
  version                    = "1.10.2"
  for_each                   = local.env.elasticache.cluster
  replication_group_id       = "${local.project}-${each.key}-backend"
  engine                     = local.env.elasticache.engine
  engine_version             = local.env.elasticache.engine_version
  node_type                  = each.value.node_type
  num_cache_clusters         = each.value.num_cache_clusters
  automatic_failover_enabled = local.env.vpc.availability_zone_total > 1 && each.value.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = local.env.vpc.availability_zone_total > 1 && each.value.num_cache_clusters > 1 ? true : false
  transit_encryption_enabled = each.value.transit_encryption_enabled
  at_rest_encryption_enabled = each.value.at_rest_encryption_enabled
  auth_token                 = random_password.elasticache.result
  maintenance_window         = each.value.maintenance_window
  apply_immediately          = each.value.apply_immediately
  vpc_id                     = module.vpc.vpc_id
  security_group_name  = "${local.project}-elasticache"
  security_group_rules = {
    ingress_vpc = {
      description = "VPC allowed traffic"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  subnet_group_name           = "${local.project}-${each.key}-subnet"
  subnet_group_description    = "${title(local.project)} subnet group"
  subnet_ids                  = module.vpc.private_subnets
  create_parameter_group      = true
  parameter_group_name        = "${local.project}-${each.key}-parameters"
  parameter_group_family      = local.env.elasticache.parameter_group_family
  parameter_group_description = "${title(local.project)} parameter group"
  parameters = [
      for name, value in local.env.elasticache.parameters : {
      name         = name
      value        = value
    }
  ]
}
