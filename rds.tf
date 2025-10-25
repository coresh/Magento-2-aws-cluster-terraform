

////////////////////////////////////////////////////////[ RDS MODULE ]////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create RDS Instance database
# # ---------------------------------------------------------------------------------------------------------------------#
module "rds" { 
  create_db_instance    = local.env.rds.create
  source                = "terraform-aws-modules/rds/aws"
  version               = "6.13.0"
  identifier            = "${local.project}-rds-instance"
  engine                = local.env.rds.engine
  engine_version        = local.env.rds.engine_version
  family                = local.env.rds.family
  major_engine_version  = local.env.rds.major_engine_version
  instance_class        = local.env.rds.instance_class
  allocated_storage     = local.env.rds.allocated_storage
  max_allocated_storage = local.env.rds.max_allocated_storage
  manage_master_user_password          = local.env.rds.manage_master_user_password
  manage_master_user_password_rotation = local.env.rds.manage_master_user_password_rotation
  master_user_password_rotation_automatically_after_days = local.env.rds.master_user_password_rotation_automatically_after_days
  db_name  = local.env.brand
  username = local.env.brand
  password = random_password.database.result
  port     = local.env.rds.port
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.rds_security_group.security_group_id]
  multi_az               = local.env.rds.multi_az
  maintenance_window              = local.env.rds.maintenance_window
  backup_window                   = local.env.rds.backup_window
  enabled_cloudwatch_logs_exports = local.env.rds.enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group           = local.env.rds.create_cloudwatch_log_group
  skip_final_snapshot                   = local.env.rds.skip_final_snapshot
  deletion_protection                   = local.env.rds.deletion_protection
  performance_insights_enabled          = local.env.rds.performance_insights_enabled
  performance_insights_retention_period = local.env.rds.performance_insights_retention_period
  create_monitoring_role                = local.env.rds.create_monitoring_role
  monitoring_interval                   = local.env.rds.monitoring_interval
  create_db_option_group    = true
  option_group_name         = "${local.project}-rds-options"
  create_db_parameter_group = true
  parameter_group_name      = "${local.project}-rds-parameters"
  parameters = [
    for name, value in local.env.rds.parameters : {
      name         = name
      value        = value
      apply_method = "immediate"
    }
  ]
}

module "rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name        = "${local.project}-rds-security"
  description = "${local.project} MySQL security group"
  vpc_id      = module.vpc.vpc_id
  ingress_with_source_security_group_id = [
    {
      from_port   = local.env.rds.port
      to_port     = local.env.rds.port
      protocol    = "tcp"
      description = "MySQL access from EC2 backend within VPC"
      source_security_group_id = module.autoscaling_security_group["backend"].security_group_id
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}
