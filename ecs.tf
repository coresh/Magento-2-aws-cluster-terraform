

/////////////////////////////////////////////////////[ ECS CLUSTER MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Cluster configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws//modules/cluster"
  for_each     = local.env.ec2
  name         = "${local.project}-${each.key}-ecs-cluster"
  autoscaling_capacity_providers = {
    (each.key) = {
      auto_scaling_group_arn         = module.asg[each.key].autoscaling_group_arn
      managed_draining               = "ENABLED"
      managed_termination_protection = "ENABLED"
      managed_scaling = {
        status                    = "ENABLED"
        maximum_scaling_step_size = local.env.asg.maximum_scaling_step_size
        minimum_scaling_step_size = local.env.ec2
        target_capacity           = local.env.ec2
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
resource "aws_service_discovery_service" "this" {
  name = "backend"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      type = "A"
      ttl  = 10
    }
   routing_policy = "MULTIVALUE"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Service configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_service" {
  source      = "terraform-aws-modules/ecs/aws//modules/service"
  for_each    = local.env.ec2
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
  cpu    = local.env.ecs[each.key].cluster_cpu
  memory = local.env.ecs[each.key].cluster_memory
  service_connect_configuration = {
    enabled = each.key == "backend" ? true : false
    namespace = aws_service_discovery_private_dns_namespace.main.arn
    service = {
      client_alias = {
        port     = local.env.ecs[each.key].container_port
        dns_name = "backend"
      }
      port_name      = "backend"
      discovery_name = "backend"
    }
  }
  runtime_platform = {
      cpu_architecture = local.env.ecs.cpu_architecture
      operating_system_family = "LINUX"
  }
  container_definitions = {
    (each.key) = {
      image  = local.env.ecs[each.key].docker_image
      cpu    = local.env.ecs[each.key].container_cpu
      memory = local.env.ecs[each.key].container_memory
      port_mappings = [
        {
          name          = local.env.ecs[each.key].container_name
          containerPort = local.env.ecs[each.key].container_port
          protocol      = local.env.ecs[each.key].protocol
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "magento"
          containerPath = "/home/${local.env.brand}/public"
          readOnly      = false
        }
      ]
      essential   = true
      environment = [{}]
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
  volume {
    name = "magento"
    efs_volume_configuration = {
      file_system_id     = aws_efs_file_system.this.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
      authorization_config = {
        access_point_id = aws_efs_access_point.this.id
        iam             = "ENABLED"
      }
    }
  }
  load_balancer = each.key == "varnish" ? {
    service = {
      target_group_arn = module.alb.target_groups.arn
      container_name   = varnish
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
