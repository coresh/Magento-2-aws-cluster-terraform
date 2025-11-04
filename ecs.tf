

/////////////////////////////////////////////////////[ ECS CLUSTER MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Cluster configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws//modules/cluster"
  for_each     = local.env.ecs.container
  name         = "${local.project}-${each.key}-ecs-cluster"
  autoscaling_capacity_providers = {
    (each.key) = {
      auto_scaling_group_arn         = module.autoscaling[each.key].autoscaling_group_arn
      managed_draining               = "ENABLED"
      managed_termination_protection = "ENABLED"
      managed_scaling = {
        status                    = "ENABLED"
        minimum_scaling_step_size = local.env.ecs.cluster.minimum_scaling_step_size
        maximum_scaling_step_size = local.env.ecs.cluster.maximum_scaling_step_size
        target_capacity           = local.env.ecs.cluster.target_capacity
      }
    }
  }
}

/////////////////////////////////////////////////////[ ECS SERVICE MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Service CloudMap discovery
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "${local.env.brand}.internal"
  vpc         = module.vpc.vpc_id
  description = "Private DNS namespace for ${local.project}"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Service configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_service" {
  source      = "terraform-aws-modules/ecs/aws//modules/service"
  for_each    = local.env.ecs.container
  name        = "${local.project}-${each.key}-ecs-service"
  cluster_arn = module.ecs_cluster[each.key].arn
  enable_execute_command     = true
  requires_compatibilities   = ["EC2"]
  capacity_provider_strategy = {
    (each.key) = {
      capacity_provider = one(keys(module.ecs_cluster[each.key].autoscaling_capacity_providers))
      weight            = 1
      base              = 1
    }
  }
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  cpu    = local.env.ecs.cluster.cpu
  memory = local.env.ecs.cluster.memory
  service_connect_configuration = each.key == "varnish" ? null : {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.this.arn
    service   = [{
      client_alias = {
        port     = local.env.ecs.container[each.key].port
        dns_name = each.key
      }
      port_name      = each.key
      discovery_name = each.key
    }]
  }
  runtime_platform = {
    cpu_architecture = local.env.ecs.cluster.cpu_architecture
    operating_system_family = "LINUX"
  }
  container_definitions = {
    (each.key) = {
      image  = "${module.ecr[each.key].repository_url}:${local.env.ecs.container[each.key].image}"
      cpu    = local.env.ecs.container[each.key].cpu
      memory = local.env.ecs.container[each.key].memory
      portMappings = [
        {
          name          = each.key
          containerPort = local.env.ecs.container[each.key].port
          hostPort      = local.env.ecs.container[each.key].port
          protocol      = local.env.ecs.container[each.key].protocol
        }
      ]
      mountPoints = each.key == "varnish" ? [] : [for name, config in local.env.efs : {
        sourceVolume  = name
        containerPath = "/home/${local.env.brand}/${name}"
        readOnly      = config.read_only
      }]
      workingDirectory = each.key == "varnish" ? null : "/home/${local.env.brand}/public/current"
      volume = each.key == "varnish" ? {} : { for name, config in local.env.efs : name => {
        name = name
        efs_volume_configuration = {
          file_system_id     = module.efs.id
          root_directory     = "/"
          transit_encryption = "ENABLED"
          authorization_config = {
            access_point_id = module.efs.access_points[name].id
            iam             = "ENABLED"
          }
        }
      }}
      essential   = true
      environment = each.key == "varnish" ? [
        {
          name  = "VARNISH_SIZE"
          value = local.env.ecs.container[each.key].memory
        }
      ] : []
      secrets = [for secret in local.env.ecs.container[each.key].secrets : {
        name      = secret
        valueFrom = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.project}/${secret}"
      }]
      readonly_root_filesystem               = true
      enable_cloudwatch_logging              = true
      create_cloudwatch_log_group            = true
      cloudwatch_log_group_name              = "/aws/ecs/${local.project}/${each.key}"
      cloudwatch_log_group_retention_in_days = 7
      log_configuration = {
        logDriver = "awslogs"
      }
    }
  }
  linux_parameters = {
    init_process_enabled = true
    tmpfs = each.key == "varnish" ? [
      {
        container_path = "/var/lib/varnish/varnishd"
        mount_options = ["exec", "noatime", "nodiratime"] 
        size = local.env.ecs.container[each.key].memory
      }
    ] : []
  }
  load_balancer = each.key == "varnish" ? {
    service = {
      target_group_arn = module.alb.target_groups[each.key].arn
      container_name   = each.key
      container_port   = 80
    }
  } : null
  subnet_ids = module.vpc.private_subnets
  task_exec_ssm_param_arns = [
    "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.project}/*"
  ]
  tasks_iam_role_statements = [
    {
      sid = "SSMParameterAccess"
      actions = [
        "ssm:GetParameters",
        "ssm:GetParameter", 
        "ssm:GetParametersByPath"
      ]
      resources = [
        "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.project}/*"
      ]
    },
    {
      sid = "EFSAccess"
      actions = [
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientMount"
      ]
      resources = [
        module.efs.arn
      ]
    }
  ]
  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = module.vpc.vpc_cidr_block
      description = "Allow HTTP"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
      description = "Allow all outbound to VPC"
    }
  }
}
