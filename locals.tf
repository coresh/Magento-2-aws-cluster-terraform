

///////////////////////////////////////////////////////////[ LOCALS ]/////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define locals
# # ---------------------------------------------------------------------------------------------------------------------#
locals {
  # Are we in us-east-1?
  use_us_east_1 = data.aws_region.current.region != "us-east-1"

  # Cloudwatch metrics alarm for resources
  metric_alarm = merge(local.env.elasticache_metric, local.env.opensearch_metric, local.env.aurora_metric)

  # Get environment name from workspace name
  environment = lower(terraform.workspace)

  # Create global project name to be assigned to all resources
  project = lower("${local.env.brand}-${local.env.codename}-${substr(local.environment, 0, 1)}")

  # Provider default tags for every resource
  default_tags = {
    Terraform    = true
    Brand        = local.env.brand
    Codename     = local.env.codename
    Config       = base64decode("TWFnZW5Y")
    Environment  = local.environment
  }

  # YAML files with variables per environment
  config_files = {
    staging    = try(file("${abspath(path.root)}/staging.config.yaml"), "")
    developer  = try(file("${abspath(path.root)}/developer.config.yaml"), "")
    production = try(file("${abspath(path.root)}/production.config.yaml"), "")
  }

  # Variables constructor to pass in root module [ var = local.env.vpc.cidr_block ]
  env = yamldecode(local.config_files[local.environment])

# # ---------------------------------------------------------------------------------------------------------------------#
# Define whitelist and blacklist IP sets
# # ---------------------------------------------------------------------------------------------------------------------#
  waf_ipset = {
    whitelist = {
      name        = "${local.project}-whitelist-ip-set"
      description = "IP set for whitelisted IP addresses"
      addresses   = local.env.waf.whitelist_ip[*]
    }
    blacklist = {
      name        = "${local.project}-blacklist-ip-set"
      description = "IP set for blacklisted IP addresses"
      addresses   = local.env.waf.blacklist_ip[*]
    }
  }

  # Define rules for whitelist and blacklist
  waf_ipset_rules = {
    allow-whitelisted-ips = {
      priority     = 0
      action       = "allow"
      ip_set_key   = "whitelist"
      metric_name  = "${local.project}-allow-whitelisted-ips"
    }
    block-blacklisted-ips = {
      priority     = 1
      action       = "block"
      ip_set_key   = "blacklist"
      metric_name  = "${local.project}-block-blacklisted-ips"
    }
  }
}
