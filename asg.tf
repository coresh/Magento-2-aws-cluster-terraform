

///////////////////////////////////////////////////[ AUTOSCALING ECS MODULE ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling" {
  source           = "terraform-aws-modules/autoscaling/aws"
  version          = "9.0.1"
  for_each         = local.env.ecs.container
  name             = "${local.project}-${each.key}-asg"
  image_id         = data.aws_ami.this.id
  instance_type    = each.value.instance_type
  security_groups  = [module.autoscaling_security_group[each.key].security_group_id]
  user_data        = base64encode(templatefile("${path.module}/user_data.tftpl", {
       ecs_cluster = "${local.project}-${each.key}-ecs-cluster",
       region      = data.aws_region.current.region
  }))
  vpc_zone_identifier    = module.vpc.private_subnets
  health_check_type      = local.env.asg.health_check_type
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_capacity
  protect_from_scale_in           = local.env.asg.protect_from_scale_in
  ignore_desired_capacity_changes = true
  create_iam_instance_profile     = true
  iam_role_name                   = "${local.project}-ECS-EC2-Role"
  iam_role_description            = "Role for ECS EC2 in ${local.project}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  use_mixed_instances_policy = local.env.asg.use_mixed_instances_policy
  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = each.value.min_size
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = local.env.asg.mixed_instances_policy.spot_allocation_strategy
    }
    launch_template = {
      override = [
        {
          instance_requirements = {
            vcpu_count = {
              min = local.env.asg.override.instance_requirements.vcpu_count.min
              max = local.env.asg.override.instance_requirements.vcpu_count.max
            }
            memory_mib = {
              min = local.env.asg.override.instance_requirements.memory_mib.min
              max = local.env.asg.override.instance_requirements.memory_mib.max
            }
            instance_generations = local.env.asg.override.instance_requirements.instance_generations
            burstable_performance = local.env.asg.override.instance_requirements.burstable_performance
          }
        }
      ]
    }
  }
  ebs_optimized     = true
  enable_monitoring = true
  block_device_mappings = [{
    device_name = "/dev/xvda"
    no_device   = 0
    ebs = {
      delete_on_termination = true
      encrypted             = true
      volume_size           = each.value.volume_size
      volume_type           = "gp3"
    }
  }]
  tag_specifications = [
  {
    resource_type = "instance"
    tags = {
        Name = "${local.project}-${each.key}-ec2"
        Shortname = each.key
        Hostname = "${each.key}.${local.env.brand}.internal"
        Environment = local.environment
      }
    },
	{
    resource_type = "volume"
    tags = {
        Name = "${local.project}-${each.key}-volume"
        Environment = local.environment
      }
    }
  ]
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      instance_warmup        = local.env.asg.instance_warmup
    }
    triggers = ["tag"]
  }
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
module "autoscaling_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "5.3.0"
  for_each    = local.env.ecs.container
  name        = "${local.project}-asg-${each.key}-security-group"
  description = "Autoscaling security group"
  vpc_id      = module.vpc.vpc_id
  computed_ingress_with_source_security_group_id = [{
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb.security_group_id
    }]
  number_of_computed_ingress_with_source_security_group_id = 1
  egress_rules = ["all-all"]
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling SNS topic email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_autoscaling_notification" "this" {
  for_each    = module.autoscaling
  group_names = [
    each.value.autoscaling_group_name
  ]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = module.sns["devops"].topic_arn
}
