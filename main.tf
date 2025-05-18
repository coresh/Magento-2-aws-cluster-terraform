//////////////////////////////////////////////////////////[ PROVIDER ]////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define provider
# # ---------------------------------------------------------------------------------------------------------------------#
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.95.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
provider "aws" {
  default_tags {
   tags = local.default_tags
 }
}
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags {
   tags = local.default_tags
 }
}

///////////////////////////////////////////////////////[ DATA RESOURCES ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define data resources
# # ---------------------------------------------------------------------------------------------------------------------#
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_ami" "this" {
  most_recent = true
  owners      = ["136693071363"]
  filter {
    name   = "name"
    values = ["debian-12-arm64*"]
  }
}
///////////////////////////////////////////////////////////[ LOCALS ]/////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define locals
# # ---------------------------------------------------------------------------------------------------------------------#
locals {
  # Are we in us-east-1?
  use_us_east_1 = data.aws_region.current.name != "us-east-1"

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

/////////////////////////////////////////////////[ AWS BUDGET NOTIFICATION ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create alert when your budget thresholds are forecasted to exceed
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_budgets_budget" "this" {
  name              = "${local.project}-budget-monthly-forecasted"
  budget_type       = "COST"
  limit_amount      = local.env.budget_limit_amount
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  dynamic "notification" {
    for_each = toset(["25", "50", "75", "100", "125", "150"])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_sns_topic_arns  = [module.sns["budget"].topic_arn]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create alert when your Cost Anomaly Detection trigger changes
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ce_anomaly_monitor" "cost" {
  name              = "${local.project}-cost-anomaly-detection"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags = {
    Name = "${local.project}-cost-anomaly-detection"
    }
}

resource "aws_ce_anomaly_subscription" "cost_alert" {
  name      = "${local.project}-cost-anomaly-alert"
  frequency = "IMMEDIATE"
  threshold_expression {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = ["15"]
      }
    }
  monitor_arn_list = [
    aws_ce_anomaly_monitor.cost.arn
  ]
  subscriber {
    type    = "SNS"
    address = module.sns["budget"].topic_arn
  }
}

##########################################################################################################################
###############################################[ INFRASTRUCTURE CONFIGURATION ]###########################################

//////////////////////////////////////////////////[ VPC NETWORKING MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create VPC and base networking layout per environment
# # ---------------------------------------------------------------------------------------------------------------------#
module "vpc" {
  # mini vpc mudule to create private subnets and nat ec2 instace per az
  source                  = "magenx/vpc/aws"
  version                 = "1.0.6"
  project                 = local.project
  enable_dns_support      = local.env.vpc.enable_dns_support
  enable_dns_hostnames    = local.env.vpc.enable_dns_hostnames
  instance_tenancy        = local.env.vpc.instance_tenancy
  availability_zone_total = local.env.vpc.availability_zone_total
  create_database_subnet  = local.env.vpc.create_database_subnet
  cidr_block              = local.env.vpc.cidr_block
  exclude_zone_ids        = local.env.vpc.exclude_zone_ids
  nat_gateway_instance_type = local.env.nat_gateway.instance_type
  nat_gateway_volume_size   = local.env.nat_gateway.volume_size
  ami_owner                 = local.env.nat_gateway.ami_owner
  ami_image                 = local.env.nat_gateway.ami_image
}

///////////////////////////////////////////////////////[ ACM SSL MODULE ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ACM certificates for cloudfront and alb
# # ---------------------------------------------------------------------------------------------------------------------#
module "acm" {
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "5.1.1"
  domain_name               = local.env.domain
  validation_method         = "DNS"
  subject_alternative_names = concat(compact(local.env.san), compact(local.env.aliases))
  create_route53_records    = false
  validate_certificate      = false
}
module "acm_cloudfront" {
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "5.1.1"
  count                     = local.use_us_east_1 ? 1 : 0
  providers                 = { aws = aws.us-east-1 }
  domain_name               = local.env.domain
  validation_method         = "DNS"
  subject_alternative_names = concat(compact(local.env.san), compact(local.env.aliases))
  create_route53_records    = false
  validate_certificate      = false
}

/////////////////////////////////////////////////////[ SNS TOPICS MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SNS topics for alerts subscription
# # ---------------------------------------------------------------------------------------------------------------------#
module "sns" {
  source   = "terraform-aws-modules/sns/aws"
  version  = "6.1.3"
  for_each = local.env.sns.topic
  name     = "${local.project}-${each.key}"
  subscriptions = {
    for email_address in each.value.email :
    "email" => {
      protocol = "email"
      endpoint = email_address
    }
  }
}

/////////////////////////////////////////////////////[ CLOUDWATCH ALARMS ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Utilization metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
module "metric_alarm" {
  source              = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version             = "5.7.1"
  for_each            = local.metric_alarm
  alarm_name          = "${local.project}-${each.value.namespace}-${each.key}-${each.value.metric_name}"
  alarm_description   = "${each.value.namespace} ${each.key} ${each.value.metric_name} utilization"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  period              = each.value.period
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  alarm_actions       = [module.sns["devops"].topic_arn]
}

/////////////////////////////////////////////////////[ S3 BUCKETS MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 buckets
# # ---------------------------------------------------------------------------------------------------------------------#
module "s3" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "4.8.0"
  for_each = local.env.s3.bucket
  bucket   = "${local.project}-${each.key}"
  acl      = "private"
  #attach_policy           = true
  #policy                  = each.value.policy
  force_destroy            = true
  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  expected_bucket_owner    = data.aws_caller_identity.current.account_id
  attach_elb_log_delivery_policy = each.key == "logs" ? true : false
  versioning = {
    enabled = each.value.versioning
  }  
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
      }
    }
  }
  intelligent_tiering = {
    general = {
      status = each.value.intelligent_tiering.status
      tiering = {
        ARCHIVE_ACCESS = { days = 90 }
      }
    }
  }
  lifecycle_rule = [
    {
      id      = "delete-unaccessed-after-90-days"
      status  = each.value.lifecycle_rule.status
      filter  = {}
      expiration = {
        days = 91
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Configure S3 buckets notifications for example to eventbridge
# # ---------------------------------------------------------------------------------------------------------------------#
module "s3_notifications" {
  source   = "terraform-aws-modules/s3-bucket/aws//modules/notification"
  for_each = local.env.s3.bucket
  bucket   = module.s3[each.key].s3_bucket_id
  eventbridge = each.value.eventbridge
}

//////////////////////////////////////////////////////[ EFS STORAGE MODULE ]//////////////////////////////////////////////

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
    posix_example = {
      name = each.key
      posix_user = {
        gid  = each.value.gid
        uid  = each.value.uid
      }
    }
    root_example = {
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

////////////////////////////////////////////////////////[ AURORA MODULE ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords for aurora master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "aurora" {
  length           = 16
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random name for aurora master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_string" "aurora" {
  length         = 8
  lower          = true
  numeric        = false
  special        = false
  upper          = false
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Aurora cluster
# # ---------------------------------------------------------------------------------------------------------------------#
module "aurora" {
  create          = local.env.aurora_create
  source          = "terraform-aws-modules/rds-aurora/aws"
  version         = "9.13.0"
  name            = "${local.project}-aurora-cluster"
  engine          = local.env.aurora.engine
  engine_version  = local.env.aurora.engine_version
  manage_master_user_password          = local.env.aurora.manage_master_user_password
  manage_master_user_password_rotation = local.env.aurora.manage_master_user_password_rotation
  master_user_password_rotation_automatically_after_days = local.env.aurora.master_user_password_rotation_automatically_after_days
  master_username = replace(local.project, "-", "")
  master_password = random_password.aurora.result
  database_name   = replace(local.project, "-", "_")
  backup_retention_period = 7
  preferred_backup_window = "02:00-05:00"
  vpc_id               = module.vpc.vpc_id
  instance_class = local.env.aurora.instance_class
  instances = {
    instance-one = {
      publicly_accessible = false
      identifier = "${local.project}-instance-one"
    }
  }
  autoscaling_enabled      = local.env.aurora.autoscaling_enabled
  autoscaling_min_capacity = local.env.aurora.autoscaling_min_capacity
  autoscaling_max_capacity = local.env.aurora.autoscaling_max_capacity
  monitoring_interval           = 60
  iam_role_name                 = "${local.project}-aurora-monitor"
  iam_role_use_name_prefix      = true
  iam_role_description          = "${local.project} RDS enhanced monitoring IAM role"
  iam_role_path                 = "/autoscaling/"
  iam_role_max_session_duration = 7200
  security_group_name  = "${local.project}-aurora-cluster"
  security_group_rules = {
    vpc_ingress = {
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
  }
  db_subnet_group_name = module.vpc.database_subnet_group_name
  enabled_cloudwatch_logs_exports = local.env.aurora.enabled_cloudwatch_logs_exports
  cluster_performance_insights_enabled          = local.env.aurora.cluster_performance_insights_enabled
  cluster_performance_insights_retention_period = local.env.aurora.cluster_performance_insights_retention_period
  skip_final_snapshot = local.env.aurora.skip_final_snapshot
  apply_immediately   = local.env.aurora.apply_immediately
  create_db_cluster_parameter_group      = true
  db_cluster_parameter_group_name        = "${local.project}-aurora-cluster-parameters"
  db_cluster_parameter_group_family      = "aurora-mysql8.0"
  db_cluster_parameter_group_description = "${local.project} cluster parameter group"
  db_cluster_parameter_group_parameters = [
    for name, value in local.env.aurora.parameters : {
      name         = name
      value        = value
      apply_method = "immediate"
    }
  ]
  create_db_parameter_group      = true
  db_parameter_group_name        = "${local.project}-aurora-instance-parameters"
  db_parameter_group_family      = "aurora-mysql8.0"
  db_parameter_group_description = "${local.project} instance parameter group"
  db_parameter_group_parameters  = [
    for name, value in local.env.aurora.parameters : {
      name         = name
      value        = value
      apply_method = "immediate"
    }
  ]
}

/////////////////////////////////////////////////////[ LAMBDA@EDGE MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Lambda@Edge package and publish
# # ---------------------------------------------------------------------------------------------------------------------#
module "media_optimization_lambda_package" {
  source         = "terraform-aws-modules/lambda/aws"
  version        = "7.20.2"
  providers      = { aws = aws.us-east-1 }
  function_name  = "${local.project}-media-optimization"
  description    = "Lambda@Edge function to optimize media before cloudfront"
  handler        = "index.handler"
  runtime        = "nodejs20.x"
  lambda_at_edge = true
  publish        = true
  create_package = true
  source_path = {
    path             = "${abspath(path.root)}/lambda"
    npm_requirements = true
  }
  hash_extra     = ""
  store_on_s3    = false
  s3_bucket      = module.s3["lambda"].s3_bucket_id
  s3_prefix      = "lambda-edge-media-optimization/"
  create_lambda_function_url = true
  authorization_type         = "AWS_IAM"
  environment_variables  = {
      s3BucketRegion             = module.s3["media"].s3_bucket_region
      originalImageBucketName    = module.s3["media"].s3_bucket_id
      transformedImageBucketName = module.s3["media-optimized"].s3_bucket_id
      transformedImageCacheTTL   = "max-age=31622400"
      maxImageSize               = "4700000"
  }
  allowed_triggers = {
    Cloudfront = {
      principal  = "cloudfront.amazonaws.com"
      source_arn = module.cloudfront.cloudfront_distribution_arn
    }
  }
}

/////////////////////////////////////////////////////[ CLOUDFRONT MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random uuid string that is intended to be used as secret header
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_uuid" "secret_header" {}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create a custom CloudFront Response Headers Policy
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudfront_response_headers_policy" "media" {
  name = "${local.project}-response-headers-media"
  cors_config {
    access_control_allow_credentials = false
    access_control_allow_headers { items = ["*"] }
    access_control_allow_methods { items = ["GET"] }
    access_control_allow_origins { items = ["*"] }
    access_control_max_age_sec  = 600
    origin_override             = false
  }

  custom_headers_config {
    items {
      header   = "x-aws-image-optimization"
      value    = "v1.0"
      override = true
    }

    items {
      header   = "vary"
      value    = "accept"
      override = true
    }
  }
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Cloudfront distribution with vpc origin and lambda
# # ---------------------------------------------------------------------------------------------------------------------#
module "cloudfront" {
  source              = "terraform-aws-modules/cloudfront/aws"
  version             = "4.1.0"
  aliases             = concat(compact(local.env.aliases))
  comment             = "${local.env.domain} media and static files"
  enabled             = true
  staging             = local.env.cloudfront.staging
  http_version        = local.env.cloudfront.http_version
  is_ipv6_enabled     = local.env.cloudfront.is_ipv6_enabled
  price_class         = local.env.cloudfront.price_class
  retain_on_delete    = local.env.cloudfront.retain_on_delete
  wait_for_deployment = local.env.cloudfront.wait_for_deployment
  continuous_deployment_policy_id = null
  create_monitoring_subscription  = local.env.cloudfront.create_monitoring_subscription
  create_origin_access_identity   = true
  origin_access_identities = {
    s3_bucket_media_optimized = "CloudFront origin access identity"
  }
  create_origin_access_control = true
  origin_access_control = {
    lambda_media_optimization = {
      description      = "Cloudfront origin access control for ${local.project} lambda function"
      origin_type      = "lambda"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }
  create_vpc_origin = true
  vpc_origin = {
    alb_vpc_origin = {
      name                   = "${local.project}-alb-vpc-origin"
      arn                    = module.alb.arn
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = {
        items    = ["TLSv1.2"]
        quantity = 1
      }
    }
  }

  origin = {
    s3_bucket_media_optimized = {
      domain_name = module.s3["media-optimized"].s3_bucket_bucket_regional_domain_name
      origin_id   = "${local.env.domain}-media-optimized"
      s3_origin_config = {
        origin_access_identity = "s3_bucket_media_optimized"
      }
    }
    lambda_media_optimization = {
      domain_name           = split("/",module.media_optimization_lambda_package.lambda_function_url)[2]
      origin_id             = "${local.env.domain}-lambda-media-optimization"
      origin_access_control = "lambda_media_optimization"
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
    }
    origin_shield = {
        enabled               = local.env.cloudfront.origin_shield_enabled
        origin_shield_region  = data.aws_region.current.name
      }
    }
    alb_vpc_origin = {
      domain_name = module.alb.dns_name
      origin_id   = "${local.project}-alb-vpc-origin"
      vpc_origin_config = {
        vpc_origin_id            = "alb_vpc_origin"
        origin_keepalive_timeout = 300
        origin_read_timeout      = 300
      }
      custom_header = [
        {
        name  = "X-${title(local.env.brand)}-Header"
        value = random_uuid.secret_header.result
        }
      ]
    }
  }
  origin_group = {
    media_optimization_group = {
      failover_status_codes      = local.env.cloudfront.failover_criteria_status_codes
      primary_member_origin_id   = "${local.env.domain}-media-optimized"
      secondary_member_origin_id = "${local.env.domain}-lambda-media-optimization"
      origin_id                  = "${local.env.domain}-media-optimization-group"
    }
  }

  ordered_cache_behavior = [ 
   {
    path_pattern     = local.env.cloudfront.path_pattern
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.env.domain}-media-optimization-group"	
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.media.id
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    viewer_protocol_policy     = "https-only"
    compress                   = false
   },
   {
    path_pattern     = "admin_*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.project}-alb-vpc-origin"	
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    viewer_protocol_policy     = "https-only"
    compress                   = true
   }
   ]
   
   default_cache_behavior = {
     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
     cached_methods   = ["GET", "HEAD"]
     target_origin_id = "${local.project}-alb-vpc-origin"
     origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
     cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
     viewer_protocol_policy   = "https-only"
     compress                 = true
  }

  logging_config = {
    bucket = module.s3["logs"].s3_bucket_bucket_domain_name
    prefix = "cloudfront"
  }
    geo_restriction = {
      restriction_type = "blacklist"
      locations        = local.env.waf.restricted_countries
  }
  viewer_certificate = {
    acm_certificate_arn      = try(module.acm_cloudfront.acm_certificate_arn, module.acm.acm_certificate_arn, null)
    ssl_support_method       = "sni-only"
    minimum_protocol_version = local.env.cloudfront.minimum_protocol_version
  }
}

/////////////////////////////////////////////////////[ WAFv2 RULES MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create AWS WAFv2 rules
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_wafv2_web_acl" "this" {
  name        = "${local.project}-waf-rules"
  provider    = aws.us-east-1
  scope       = "CLOUDFRONT"
  description = "${title(local.project)} WAFv2 Rules"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name = "${local.project}-waf-rules"
    sampled_requests_enabled = true
  }
  dynamic "rule" {
    for_each = local.waf_ipset_rules
    content {
      name     = rule.key
      priority = rule.value.priority
      action {
        dynamic "allow" {
          for_each = rule.value.action == "allow" ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.this[rule.value.ip_set_key].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.metric_name
        sampled_requests_enabled   = true
      }
    }
  }
  rule {
    name     = "${local.project}-country-based"
    priority = 2
    action {
      block {}
    }
    statement {
      geo_match_statement {
        country_codes = local.env.waf.restricted_countries
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.project}-country-based"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "${local.project}-rate-based"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
       limit              = 500
       aggregate_key_type = "IP"
       evaluation_window_sec = 120
       }
     }
      visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.project}-rate-rule"
      sampled_requests_enabled   = true
    }
   }
  rule {
    name = "AWSManagedRulesCommonRule"
    priority = 4
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${local.project}-AWSManagedRulesCommonRule"
      sampled_requests_enabled = true
    }
  }
  rule {
    name = "AWSManagedRulesAmazonIpReputation"
    priority = 5
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${local.project}-AWSManagedRulesAmazonIpReputation"
      sampled_requests_enabled = true
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create AWS WAFv2 IP set
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_wafv2_ip_set" "this" {
  provider           = aws.us-east-1
  for_each           = local.waf_ipset
  name               = each.value.name
  description        = each.value.description
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = each.value.addresses
}

//////////////////////////////////////////////[ APPLICATION LOAD BALANCER MODULE ]////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ALB internal in private network as vpc origin
# # ---------------------------------------------------------------------------------------------------------------------#
module "alb" {
  source   = "terraform-aws-modules/alb/aws"
  version  = "9.16.0"
  internal = true
  name     = "${local.project}-alb"
  vpc_id   = module.vpc.vpc_id
  subnets  = module.vpc.private_subnets
  client_keep_alive = 300
  enable_deletion_protection = local.env.alb.enable_deletion_protection
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  access_logs = {
    bucket = module.s3["logs"].s3_bucket_id
    prefix = "ALB_logs"
  }
  target_groups = {
    frontend = {
      name                 = "${local.project}-${local.env.alb.target_group}"
      port                 = 80
      protocol             = "HTTP"
      vpc_id               = module.vpc.vpc_id
      target_type          = local.env.alb.target_type
      deregistration_delay = 300
      create_attachment    = false
      health_check = {
        path                = "/${local.env.alb.health_check_path}"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 3
        unhealthy_threshold = 2
        matcher             = "200"
      }
    }
  }
  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = local.env.alb.ssl_policy
      certificate_arn = module.acm.acm_certificate_arn
      fixed_response = {
        content_type = "text/plain"
        message_body = local.env.alb.fixed_response.message_body
        status_code  = local.env.alb.fixed_response.status_code
        order = 1
      }
      rules = {
        frontend = {
          priority = 30
          actions = [{
            type             = "forward"
            target_group_key = "frontend"
            order = 1
          }]
          conditions = [{
            host_header = {
              values = [local.env.domain]
            }
          },
          {
            http_header = {
              http_header_name = "X-${title(local.env.brand)}-Secret"
              values = [random_uuid.secret_header.result]
            }
          }]
        }
      }
    }
    http = {
      port     = 80
      protocol = "HTTP"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
  }

/////////////////////////////////////////////////////[ AUTOSCALING MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling_ecs" {
  source           = "terraform-aws-modules/autoscaling/aws"
  version          = "8.3.0"
  name             = "${local.project}-ecs-autoscaling"
  image_id         = data.aws_ami.this.id
  instance_type    = local.env.asg.instance_type
  security_groups  = [module.autoscaling_ecs_security_group.security_group_id]
  user_data        = base64encode(
<<-END
#!/bin/bash
# ecs cluster configuration
mkdir -p /etc/ecs
echo "ECS_CLUSTER=${local.project}-ecs-cluster" > /etc/ecs/ecs.config
echo "ECS_LOGLEVEL=debug" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_TASK_IAM_ROLE=true" >> /etc/ecs/ecs.config
# install docker
apt update
apt -yq install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -yq install docker-ce docker-ce-cli containerd.io
# install ecs agent
cd /tmp/
curl -O https://s3.${data.aws_region.current.name}.amazonaws.com/amazon-ecs-agent-${data.aws_region.current.name}/amazon-ecs-init-latest.$(dpkg --print-architecture).deb
dpkg -i amazon-ecs-init-latest.$(dpkg --print-architecture).deb
systemctl enable ecs
systemctl start ecs
# install ssm manager
cd /tmp/
wget -q https://s3.${data.aws_region.current.name}.amazonaws.com/amazon-ssm-${data.aws_region.current.name}/latest/debian_$(dpkg --print-architecture)/amazon-ssm-agent.deb
dpkg -i amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
END
)
  vpc_zone_identifier    = module.vpc.private_subnets
  health_check_type      = local.env.asg.health_check_type
  min_size               = local.env.asg.min_size
  max_size               = local.env.asg.max_size
  desired_capacity       = local.env.asg.desired_capacity
  protect_from_scale_in           = true
  use_mixed_instances_policy      = false
  ignore_desired_capacity_changes = true
  create_iam_instance_profile     = true
  iam_role_name                   = "${local.project}-ECS-EC2-Role"
  iam_role_description            = "ECS role for ${local.project}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  block_device_mappings = [{
      device_name = "/dev/xvda"
      no_device   = 0
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 50
        volume_type           = "gp3"
      }
    }]
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create security group for Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling_ecs_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "5.3.0"
  name        = "${local.project}-ecs-autoscaling-security-group"
  description = "Autoscaling ECS security group"
  vpc_id      = module.vpc.vpc_id
  computed_ingress_with_source_security_group_id = [{
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb.security_group_id
    }]
  number_of_computed_ingress_with_source_security_group_id = 1
  egress_rules = ["all-all"]
}

/////////////////////////////////////////////////////[ ECS CLUSTER MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Cluster configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws//modules/cluster"
  cluster_name = "${local.project}-ecs-cluster"
  default_capacity_provider_use_fargate = false
  autoscaling_capacity_providers = {
    frontend = {
      auto_scaling_group_arn         = module.autoscaling_ecs.autoscaling_group_arn
      managed_termination_protection = "ENABLED"
      managed_scaling = {
        maximum_scaling_step_size = 4
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 60
      }
      default_capacity_provider_strategy = {
        weight = 60
        base   = 20
      }
    }
  }
}

/////////////////////////////////////////////////////[ ECS CLUSTER MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Service CloudMap discovery
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_service_discovery_private_dns_namespace" "ecs_service" {
  name        = "${local.env.brand}.internal"
  vpc         = module.vpc.vpc_id
  description = "Private DNS namespace for ${local.project}"
}
resource "aws_service_discovery_service" "ecs_service" {
  name = "ecs_service"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ecs_service.id
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Service configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_service" {
  source      = "terraform-aws-modules/ecs/aws//modules/service"
  name        = "${local.project}-ecs-service"
  cluster_arn = module.ecs_cluster.arn
  enable_execute_command     = true
  requires_compatibilities   = ["EC2"]
  capacity_provider_strategy = {
    frontend = {
      capacity_provider = keys(module.ecs_cluster.autoscaling_capacity_providers)[0]
      weight            = 1
      base              = 1
    }
  }
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  cpu    = local.env.ecs.cluster_cpu
  memory = local.env.ecs.cluster_memory
  service_registries = [{
    registry_arn = aws_service_discovery_service.ecs_service.arn
  }]
  container_definitions = {
    (local.env.ecs.container_name) = {
      image  = local.env.ecr.docker_image
      cpu    = local.env.ecs.container_cpu
      memory = local.env.ecs.container_memory
      runtime_platform = {
        cpu_architecture = local.env.ecs.cpu_architecture
        operating_system_family = "LINUX"
      }
      port_mappings = [
        {
          name          = local.env.ecs.container_name
          containerPort = local.env.ecs.container_port
          protocol      = local.env.ecs.protocol
        }
      ]
      environment = [
        {
          name  = "OPENSEARCH_HOST"
          value = module.opensearch.domain_endpoint
        },
        {
          name  = "OPENSEARCH_PASSWORD"
          value = random_password.opensearch.result
        },
        {
          name  = "OPENSEARCH_USER"
          value = random_string.opensearch.result
        },
        {
          name  = "ELASTICACHE_SESSION_HOST"
          value = module.elasticache["session"].replication_group_primary_endpoint_address
        },
        {
          name  = "ELASTICACHE_CACHE_HOST"
          value = module.elasticache["cache"].replication_group_primary_endpoint_address
        },
        {
          name  = "ELASTICACHE_PASSWORD"
          value = random_password.elasticache.result
        },
        {
          name  = "DATABASE_HOST"
          value = module.aurora.cluster_endpoint
        },
        {
          name  = "DATABASE_NAME"
          value = module.aurora.cluster_database_name
        },
        {
          name  = "DATABASE_USER"
          value = module.aurora.cluster_master_username
        },
        {
          name  = "DATABASE_PASSWORD"
          value = random_password.aurora.result
        },
      ]
      readonly_root_filesystem               = true
      enable_cloudwatch_logging              = true
      create_cloudwatch_log_group            = true
      cloudwatch_log_group_name              = "/aws/ecs/${local.project}/${local.env.ecs.container_name}"
      cloudwatch_log_group_retention_in_days = 7
      log_configuration = {
        logDriver = "awslogs"
      }
    }
  }
  load_balancer = {
    service = {
      target_group_arn = values(module.alb.target_groups)[0].arn
      container_name   = local.env.ecs.container_name
      container_port   = local.env.ecs.container_port
    }
  }
  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_http_ingress = {
      type                     = "ingress"
      from_port                = local.env.ecs.container_port
      to_port                  = local.env.ecs.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
  }
}
