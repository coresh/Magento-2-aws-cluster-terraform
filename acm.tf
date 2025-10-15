

///////////////////////////////////////////////////////[ ACM SSL MODULE ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ACM certificates for cloudfront and alb
# # ---------------------------------------------------------------------------------------------------------------------#
module "acm" {
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "6.1.0"
  domain_name               = local.env.domain
  validation_method         = "DNS"
  subject_alternative_names = concat(compact(local.env.san), compact(local.env.aliases))
  create_route53_records    = false
  validate_certificate      = false
}
module "acm_cloudfront" {
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "6.1.0"
  count                     = local.use_us_east_1 ? 1 : 0
  providers                 = { aws = aws.us-east-1 }
  domain_name               = local.env.domain
  validation_method         = "DNS"
  subject_alternative_names = concat(compact(local.env.san), compact(local.env.aliases))
  create_route53_records    = false
  validate_certificate      = false
}
