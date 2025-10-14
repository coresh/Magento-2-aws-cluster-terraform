

//////////////////////////////////////////////////[ VPC NETWORKING MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create VPC and base networking layout per environment
# # ---------------------------------------------------------------------------------------------------------------------#
module "vpc" {
  # mini vpc mudule to create private subnets and nat ec2 instace per az
  source                  = "magenx/vpc/aws"
  version                 = "1.1.2"
  project                 = local.project
  enable_dns_support      = local.env.vpc.enable_dns_support
  enable_dns_hostnames    = local.env.vpc.enable_dns_hostnames
  instance_tenancy        = local.env.vpc.instance_tenancy
  availability_zone_total = local.env.vpc.availability_zone_total
  create_database_subnet  = local.env.vpc.create_database_subnet
  cidr_block              = local.env.vpc.cidr_block
  exclude_zone_ids        = local.env.vpc.exclude_zone_ids
  nat_gateway_instance_type = local.env.nat_gateway.instance_type
  nat_gateway_volume_size   = local.env.nat_gateway.volume_size
  ami_owner                 = local.env.nat_gateway.ami_owner
  ami_image                 = local.env.nat_gateway.ami_image
}
