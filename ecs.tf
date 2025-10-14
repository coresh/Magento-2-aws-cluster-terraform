

/////////////////////////////////////////////////////[ ECS CLUSTER MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ECS Cluster configuration
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws//modules/cluster"
  name = "${local.project}-ecs-cluster"
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
  name = "service"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      type = "A"
      ttl  = 10
    }
   routing_policy = "MULTIVALUE"
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
  service_registries = {
      container_name = local.env.ecs.container_name
      container_port = local.env.ecs.container_port
      registry_arn   = aws_service_discovery_service.this.arn
  }
  runtime_platform = {
      cpu_architecture = local.env.ecs.cpu_architecture
      operating_system_family = "LINUX"
  }
  container_definitions = {
    (local.env.ecs.container_name) = {
      image  = local.env.ecr.docker_image
      cpu    = local.env.ecs.container_cpu
      memory = local.env.ecs.container_memory
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
          value = try(module.opensearch.domain_endpoint, "opensearch.${local.env.brand}.internal", "empty")
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
          value = try(module.elasticache["session"].replication_group_primary_endpoint_address, "redis.${local.env.brand}.internal", "empty")
        },
        {
          name  = "ELASTICACHE_CACHE_HOST"
          value = try(module.elasticache["cache"].replication_group_primary_endpoint_address, "redis.${local.env.brand}.internal", "empty")
        },
        {
          name  = "ELASTICACHE_PASSWORD"
          value = random_password.elasticache.result
        },
        {
          name  = "DATABASE_HOST"
          value = try(module.aurora.cluster_endpoint, module.rds.db_instance_endpoint, "empty")
        },
        {
          name  = "DATABASE_NAME"
          value = try(module.aurora.cluster_database_name,module.rds.db_instance_name, "empty")
        },
        {
          name  = "DATABASE_USER"
          value = try(module.aurora.cluster_master_username, module.rds.db_instance_username, "empty")
        },
        {
          name  = "DATABASE_PASSWORD"
          value = random_password.database.result
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
  security_group_ingress_rules = {
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
