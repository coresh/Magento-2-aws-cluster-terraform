

//////////////////////////////////////////////////////[ OPENSEARCH MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords for opensearch master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "opensearch" {
  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random name for opensearch master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_string" "opensearch" {
  length         = 7
  lower          = true
  numeric        = false
  special        = false
  upper          = false
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for opensearch env
# # ---------------------------------------------------------------------------------------------------------------------#
locals {
  opensearch = {
    OPENSEARCH_ADMIN_USERNAME                    = random_string.opensearch.result
    OPENSEARCH_ADMIN_PASSWORD                    = random_password.opensearch.result
    OPENSEARCH_DOMAIN_ARN                        = try(module.opensearch.domain_arn, null)
    OPENSEARCH_DOMAIN_ID                         = try(module.opensearch.domain_id, null)
    OPENSEARCH_DOMAIN_ENDPOINT                   = try(module.opensearch.domain_endpoint, null)
    OPENSEARCH_DOMAIN_DASHBOARD_ENDPOINT         = try(module.opensearch.domain_dashboard_endpoint, null)
    OPENSEARCH_URL                               = "https://${try(module.opensearch.domain_endpoint, "")}:443"
    OPENSEARCH_DASHBOARD_URL                     = "https://${try(module.opensearch.domain_dashboard_endpoint, "")}"
  }
}

resource "aws_ssm_parameter" "opensearch" {
  for_each    = local.opensearch
  name        = "/${local.project}/${each.key}"
  description = "OpenSearch parameter: ${each.key}"
  type        = "String"
  value       = each.value
  tags = {
    Service   = "opensearch"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Opensearch cluster
# # ---------------------------------------------------------------------------------------------------------------------#
module "opensearch" {
  create           = local.env.opensearch.create
  source           = "terraform-aws-modules/opensearch/aws"
  version          = "2.2.0"
  domain_name      = "${local.project}-opensearch"
  engine_version   = local.env.opensearch.engine_version
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }
  auto_tune_options = {
    desired_state = local.env.opensearch.auto_tune_options.desired_state
  }
  advanced_security_options = {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = true
    master_user_options = {
      master_user_name     = random_string.opensearch.result
      master_user_password = random_password.opensearch.result
    }
  }
  domain_endpoint_options = {
    enforce_https         = true
    tls_security_policy   = local.env.opensearch.tls_security_policy
  }
  encrypt_at_rest = {
    enabled = true
  }
  node_to_node_encryption = {
    enabled = true
  }
  cluster_config = {
    instance_count           = local.env.opensearch.instance_count
    instance_type            = local.env.opensearch.instance_type
    dedicated_master_enabled = local.env.opensearch.dedicated_master_enabled
    dedicated_master_type    = local.env.opensearch.dedicated_master_type
    warm_enabled             = local.env.opensearch.warm_enabled
    warm_count               = local.env.opensearch.warm_enabled ? local.env.opensearch.warm_count : null
    warm_type                = local.env.opensearch.warm_enabled ? local.env.opensearch.warm_type : null
    node_options = {
      coordinator = {
        node_config = {
          enabled = local.env.opensearch.node_options.node_config.enabled
          count   = local.env.opensearch.node_options.node_config.enabled ? local.env.opensearch.node_options.node_config.count : null
          type    = local.env.opensearch.node_options.node_config.enabled ? local.env.opensearch.node_options.node_config.type : null
        }
      }
    }
    multi_az_with_standby_enabled = local.env.opensearch.multi_az_with_standby_enabled
    zone_awareness_enabled = local.env.vpc.availability_zone_total > 1 && local.env.opensearch.instance_count > 1 ? true : false
    zone_awareness_config = {
        availability_zone_count = local.env.vpc.availability_zone_total > 1 ? local.env.vpc.availability_zone_total : null
      }
  }
  ebs_options = {
    ebs_enabled = local.env.opensearch.ebs_enabled
    volume_type = local.env.opensearch.volume_type
    volume_size = local.env.opensearch.volume_size
  }
  log_publishing_options = [
    { log_type = "INDEX_SLOW_LOGS" },
    { log_type = "SEARCH_SLOW_LOGS" },
    { log_type = "ES_APPLICATION_LOGS" },
  ]
  ip_address_type = local.env.opensearch.ip_address_type
  software_update_options = {
    auto_software_update_enabled = local.env.opensearch.auto_software_update_enabled
  }
  vpc_options = {
    subnet_ids = local.env.vpc.availability_zone_total > 1 && local.env.opensearch.instance_count > 1 ? module.vpc.private_subnets : slice(module.vpc.private_subnets, 0, 1)
  }
  security_group_name  = "${local.project}-opensearch"
  security_group_rules = {
    ingress_443 = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "Opensearch HTTPS access from VPC"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  access_policy_statements = [
  {
    effect = "Allow"
    actions = ["es:*"]
    principals = [{
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }]
    resources = ["arn:aws:es:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:domain/*"]
  }
]
}
