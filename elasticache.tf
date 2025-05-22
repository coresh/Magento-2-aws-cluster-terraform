

/////////////////////////////////////////////////////[ ELASTICACHE MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "elasticache" {
  length           = 16
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Elasticache redis replication group
# # ---------------------------------------------------------------------------------------------------------------------#
module "elasticache" {
  create                     = local.env.elasticache_create
  source                     = "terraform-aws-modules/elasticache/aws"
  version                    = "1.6.0"
  for_each                   = local.env.elasticache
  replication_group_id       = "${local.project}-${each.key}-backend"
  engine_version             = "7.1"
  node_type                  = each.value.node_type
  num_cache_clusters         = each.value.num_cache_clusters
  automatic_failover_enabled = local.env.vpc.availability_zone_total > 1 && each.value.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = local.env.vpc.availability_zone_total > 1 && each.value.num_cache_clusters > 1 ? true : false
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.elasticache.result
  maintenance_window         = "sun:05:00-sun:09:00"
  apply_immediately          = true
  vpc_id                     = module.vpc.vpc_id
  security_group_name  = "${local.project}-elasticache"
  security_group_rules = {
    ingress_vpc = {
      description = "VPC allowed traffic whitelist"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  subnet_group_name           = "${local.project}-${each.key}-subnet"
  subnet_group_description    = "${title(local.project)} subnet group"
  subnet_ids                  = module.vpc.private_subnets
  create_parameter_group      = true
  parameter_group_name        = "${local.project}-${each.key}-parameters"
  parameter_group_family      = "redis7"
  parameter_group_description = "${title(local.project)} parameter group"
  parameters = [
    {
      name  = "maxmemory-policy"
      value = "allkeys-lru"
    }
  ]
}
