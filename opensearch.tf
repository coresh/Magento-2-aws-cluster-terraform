

//////////////////////////////////////////////////////[ OPENSEARCH MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords for opensearch master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "opensearch" {
  length           = 16
  lower            = true
  upper            = true
  min_lower        = 1
  min_upper        = 1
  numeric          = true
  special          = true
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
# Create Opensearch cluster
# # ---------------------------------------------------------------------------------------------------------------------#
module "opensearch" {
  create           = local.env.opensearch_create
  source           = "terraform-aws-modules/opensearch/aws"
  version          = "1.7.0"
  domain_name      = "${local.project}-opensearch"
  engine_version   = local.env.opensearch.engine_version
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
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
    node_options = {
      coordinator = {
        node_config = {
          enabled = local.env.opensearch.node_options.node_config
          count   = local.env.opensearch.node_options.count
          type    = local.env.opensearch.node_options.type
        }
      }
    }
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
    subnet_ids = module.vpc.private_subnets
  }
  vpc_endpoints = {
    one = {
      subnet_ids = module.vpc.private_subnets
    }
  }
  security_group_name  = "${local.project}-opensearch"
  security_group_rules = {
    ingress_443 = {
      type        = "ingress"
      description = "Opensearch HTTPS access from VPC"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
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
    resources = ["arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/*"]
  }
]
}
