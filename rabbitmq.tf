


/////////////////////////////////////////////////////[ AMAZON MQ BROKER ]/////////////////////////////////////////////////
# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random password
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_password" "rabbitmq" {
  length           = 16
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!&#$"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RabbitMQ - queue message broker
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_mq_broker" "this" {
  broker_name        = "${local.project}-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = local.env.rabbitmq.engine_version
  host_instance_type = local.env.rabbitmq.host_instance_type
  security_groups    = [module.rabbitmq_security_group.security_group_id]
  subnet_ids         = module.vpc.private_subnets
  user {
    username         = local.env.brand
    password         = random_password.rabbitmq.result
  }
  configuration {
    id       = aws_mq_configuration.this.id
    revision = aws_mq_configuration.this.latest_revision
  }
  encryption_options {
    use_aws_owned_key = local.env.rabbitmq.encryption_options.use_aws_owned_key
  }
  publicly_accessible = local.env.rabbitmq.publicly_accessible
  auto_minor_version_upgrade = local.env.rabbitmq.auto_minor_version_upgrade
  maintenance_window_start_time {
    day_of_week = local.env.rabbitmq.maintenance_window_start_time.day_of_week
    time_of_day = local.env.rabbitmq.maintenance_window_start_time.time_of_day
    time_zone   = local.env.rabbitmq.maintenance_window_start_time.time_zone
  }
  logs {
    general = local.env.rabbitmq.logs.general
  }
  tags = {
    Name   = "${local.project}-rabbitmq"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RabbitMQ - queue message broker configuration
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_mq_configuration" "this" {
  name           = "${local.project}-rabbitmq-configuration"
  description    = "RabbitMQ Configuration for ${local.project}"
  engine_type    = "RabbitMQ"
  engine_version = local.env.rabbitmq.engine_version

  data = <<DATA
# Default RabbitMQ delivery acknowledgement timeout is 30 minutes in milliseconds
consumer_timeout = 1800000
DATA
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create RabbitMQ - queue message broker security group
# # ---------------------------------------------------------------------------------------------------------------------#
module "rabbitmq_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "5.3.0"
  name        = "${local.project}-rabbitmq-sg"
  description = "Security group for ${local.project} RabbitMQ cluster"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port   = 5672
      to_port     = 5672
      protocol    = "tcp"
      description = "RabbitMQ AMQP from application servers"
      source_security_group_id = module.autoscaling_security_group["backend"].security_group_id
    },
    {
      from_port   = 5671
      to_port     = 5671
      protocol    = "tcp"
      description = "RabbitMQ AMQP SSL from application servers"
      source_security_group_id = module.autoscaling_security_group["backend"].security_group_id
    },
    {
      from_port   = 15672
      to_port     = 15672
      protocol    = "tcp"
      description = "RabbitMQ Management UI"
      source_security_group_id = module.autoscaling_security_group["backend"].security_group_id
    },
    {
      from_port   = 25672
      to_port     = 25672
      protocol    = "tcp"
      description = "RabbitMQ Erlang distribution for clustering"
      source_security_group_id = module.rabbitmq_security_group.security_group_id
    },
    {
      from_port   = 4369
      to_port     = 4369
      protocol    = "tcp"
      description = "RabbitMQ EPMD for clustering"
      source_security_group_id = module.rabbitmq_security_group.security_group_id
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
  tags = {
    Name = "${local.project}-rabbitmq-sg"
  }

}


