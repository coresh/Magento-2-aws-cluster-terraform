

///////////////////////////////////////////////////[ AUTOSCALING ECS MODULE ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Locals 
# # ---------------------------------------------------------------------------------------------------------------------#

locals {

  user_data = <<-END
    #!/bin/bash
    ## Base system updates
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    apt-get install -y ca-certificates curl syslog-ng
    ## install ssm manager
    cd /tmp/
    curl -O https://s3.${data.aws_region.current.region}.amazonaws.com/amazon-ssm-${data.aws_region.current.region}/latest/debian_$(dpkg --print-architecture)/amazon-ssm-agent.deb
    dpkg -i amazon-ssm-agent.deb
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  END
  
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling" {
  source           = "terraform-aws-modules/autoscaling/aws"
  version          = "9.0.1"
  for_each         = local.env.ec2
  name             = "${local.project}-${each.key}-asg"
  image_id         = data.aws_ami.this.id
  instance_type    = each.value.instance_type
  security_groups  = [module.autoscaling_security_group[each.key].security_group_id]
  user_data        = base64encode(local.user_data)
  vpc_zone_identifier    = module.vpc.private_subnets
  health_check_type      = local.env.asg.health_check_type
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_capacity
  protect_from_scale_in           = local.env.asg.protect_from_scale_in
  use_mixed_instances_policy      = false
  ignore_desired_capacity_changes = true
  create_iam_instance_profile     = true
  iam_role_name                   = "${local.project}-EC2-Role"
  iam_role_description            = "Role for EC2 in ${local.project}"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.alb[each.key].target_groups[each.key].arn
      traffic_source_type       = "elbv2"
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
        InstanceName = each.key
        Hostname = "${each.key}.${local.env.brand}.internal"
      }
    },
	{
    resource_type = "volume"
    tags = {
        Name = "${local.project}-${each.key}-volume"
      }
    }
  ]
  scaling_policies = {
    cpu-target-tracking = {
      name               = "${local.project}-cpu-target-tracking"
      policy_type        = "TargetTrackingScaling"
      adjustment_type    = "ChangeInCapacity"
      
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = local.env.asg.target_tracking_configuration.predefined_metric_type
        }
        target_value     = local.env.asg.target_tracking_configuration.target_value
        disable_scale_in = local.env.asg.target_tracking_configuration.disable_scale_in
      }
    }
  }
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
    triggers = ["tag"]
  }
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create security group for Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "5.3.0"
  for_each    = local.env.ec2
  name        = "${local.project}-asg-${each.key}-security-group"
  description = "Autoscaling security group"
  vpc_id      = module.vpc.vpc_id
  computed_ingress_with_source_security_group_id = [{
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb[each.key].security_group_id
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