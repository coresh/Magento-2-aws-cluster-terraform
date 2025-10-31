module "ecs_service" {
  source      = "terraform-aws-modules/ecs/aws//modules/service"
  for_each    = local.env.ecs.container
  name        = "${local.project}-${each.key}-ecs-service"
  cluster_arn = module.ecs_cluster[each.key].arn
  enable_execute_command     = true
  requires_compatibilities   = ["EC2"]
  capacity_provider_strategy = {
    (each.key) = {
      capacity_provider = keys(module.ecs_cluster[each.key].autoscaling_capacity_providers)
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
  service_connect_configuration = each.key == "backend" ? {
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
  } : null 
  runtime_platform = {
    cpu_architecture = local.env.ecs.cluster.cpu_architecture
    operating_system_family = "LINUX"
  }
  container_definitions = {
    (each.key) = {
      image  = local.env.ecs.container[each.key].image
      cpu    = local.env.ecs.container[each.key].cpu
      memory = local.env.ecs.container[each.key].memory
      port_mappings = [
        {
          name          = each.key
          containerPort = local.env.ecs.container[each.key].port
          protocol      = local.env.ecs.container[each.key].protocol
        }
      ]
      mountPoints = each.key == "varnish" ? [] : [for name, config in local.env.efs : {
        sourceVolume  = name
        containerPath = "/home/${local.env.brand}/${name}"
        readOnly      = config.read_only
      }]
      workingDirectory = each.key == "backend" ? "/home/${local.env.brand}/public/current" : null
      essential        = true
      secrets = [for secret in local.env.ecs[each.key].secrets : {
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
  volume = each.key == "varnish" ? {} : { for name, config in local.env.efs : name => {
    name = name
    efs_volume_configuration = {
      file_system_id     = module.efs.id
      root_directory     = module.efs.access_points[name].root_directory_path
      transit_encryption = "ENABLED"
      authorization_config = {
        access_point_id = module.efs.access_points[name].id
        iam             = "ENABLED"
      }
    }
  }}  
  load_balancer = each.key == "varnish" ? {
    service = {
      target_group_arn = module.alb.target_groups.arn
      container_name   = each.key
      container_port   = 80
    }
  } : null
  subnet_ids = module.vpc.private_subnets
  security_group_ingress_rules = {
    alb_http_ingress = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      description                  = "Service port"
      referenced_security_group_id = module.alb.security_group_id
    }
  }
}
