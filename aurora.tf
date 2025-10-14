

/////////////////////////////////////////////////////[ AURORA RDS MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random passwords for database master user
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "database" {
  length           = 16
  lower            = true
  upper            = true
  numeric          = true
  special          = true
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Aurora cluster
# # ---------------------------------------------------------------------------------------------------------------------#
module "aurora" {
  create          = local.env.aurora_create
  source          = "terraform-aws-modules/rds-aurora/aws"
  version         = "9.16.0"
  name            = "${local.project}-aurora-cluster"
  engine          = local.env.aurora.engine
  engine_version  = local.env.aurora.engine_version
  manage_master_user_password          = local.env.aurora.manage_master_user_password
  manage_master_user_password_rotation = local.env.aurora.manage_master_user_password_rotation
  master_user_password_rotation_automatically_after_days = local.env.aurora.master_user_password_rotation_automatically_after_days
  master_username = replace(local.project, "-", "")
  master_password = random_password.database.result
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
  iam_role_path                 = "/monitoring/"
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
