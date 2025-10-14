

///////////////////////////////////////////////////[ AUTOSCALING ECS MODULE ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Autoscaling group
# # ---------------------------------------------------------------------------------------------------------------------#
module "autoscaling_ecs" {
  source           = "terraform-aws-modules/autoscaling/aws"
  version          = "9.0.1"
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
curl -O https://s3.${data.aws_region.current.region}.amazonaws.com/amazon-ecs-agent-${data.aws_region.current.region}/amazon-ecs-init-latest.$(dpkg --print-architecture).deb
dpkg -i amazon-ecs-init-latest.$(dpkg --print-architecture).deb
systemctl enable ecs
systemctl start ecs
# install ssm manager
cd /tmp/
wget -q https://s3.${data.aws_region.current.region}.amazonaws.com/amazon-ssm-${data.aws_region.current.region}/latest/debian_$(dpkg --print-architecture)/amazon-ssm-agent.deb
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
