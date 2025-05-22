

//////////////////////////////////////////////[ APPLICATION LOAD BALANCER MODULE ]////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ALB internal in private network as vpc origin
# # ---------------------------------------------------------------------------------------------------------------------#
module "alb" {
  source   = "terraform-aws-modules/alb/aws"
  version  = "9.16.0"
  internal = true
  name     = "${local.project}-alb"
  vpc_id   = module.vpc.vpc_id
  subnets  = module.vpc.private_subnets
  client_keep_alive = 300
  enable_deletion_protection = local.env.alb.enable_deletion_protection
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }
  access_logs = {
    bucket = module.s3["logs"].s3_bucket_id
    prefix = "ALB_logs"
  }
  target_groups = {
    frontend = {
      name                 = "${local.project}-${local.env.alb.target_group}"
      port                 = 80
      protocol             = "HTTP"
      vpc_id               = module.vpc.vpc_id
      target_type          = local.env.alb.target_type
      deregistration_delay = 300
      create_attachment    = false
      health_check = {
        path                = "/${local.env.alb.health_check_path}"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 3
        unhealthy_threshold = 2
        matcher             = "200"
      }
    }
  }
  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = local.env.alb.ssl_policy
      certificate_arn = module.acm.acm_certificate_arn
      fixed_response = {
        content_type = "text/plain"
        message_body = local.env.alb.fixed_response.message_body
        status_code  = local.env.alb.fixed_response.status_code
        order = 1
      }
      rules = {
        frontend = {
          priority = 30
          actions = [{
            type             = "forward"
            target_group_key = "frontend"
            order = 1
          }]
          conditions = [{
            host_header = {
              values = [local.env.domain]
            }
          },
          {
            http_header = {
              http_header_name = "X-${title(local.env.brand)}-Secret"
              values = [random_uuid.secret_header.result]
            }
          }]
        }
      }
    }
    http = {
      port     = 80
      protocol = "HTTP"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
  }
