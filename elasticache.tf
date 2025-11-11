

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
  elasticache = merge([
    for elasticache_key, elasticache_output in module.elasticache : {
    "ELASTICACHE_${upper(elasticache_key)}_REPLICATION_GROUP_ARN"                      = elasticache_output.replication_group_arn
    "ELASTICACHE_${upper(elasticache_key)}_REPLICATION_GROUP_ID"                       = elasticache_output.replication_group_id
    "ELASTICACHE_${upper(elasticache_key)}_REPLICATION_GROUP_PRIMARY_ENDPOINT_ADDRESS" = elasticache_output.replication_group_primary_endpoint_address
    "ELASTICACHE_${upper(elasticache_key)}_REPLICATION_GROUP_READER_ENDPOINT_ADDRESS"  = elasticache_output.replication_group_reader_endpoint_address
    }
  ]...)
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
  automatic_failover_enabled = local.env.elasticache.multi_az
  multi_az_enabled           = local.env.elasticache.multi_az
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
  subnet_ids                  = local.env.elasticache.multi_az ? module.vpc.private_subnets : [module.vpc.primary_private_subnet_id]
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
