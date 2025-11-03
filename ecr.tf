

/////////////////////////////////////////////////////[ AWS ECR REPOSITORY ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ecr repository
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecr" {
  source            = "terraform-aws-modules/ecr/aws"
  version           = "3.1.0"
  for_each          = local.env.ecr.repository
  create            = local.env.ecr.create
  create_repository = each.value.create_repository
  repository_type   = local.env.ecr.repository_type
  repository_name   = "${local.project}-images/${each.key}"
  repository_image_tag_mutability = each.value.repository_image_tag_mutability
  repository_force_delete         = each.value.repository_force_delete
  create_repository_policy        = local.env.ecr.create_repository_policy
  attach_repository_policy        = local.env.ecr.attach_repository_policy
  create_lifecycle_policy         = local.env.ecr.create_lifecycle_policy
  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${local.env.ecr.keep_images} images"
      action = {
        type = "expire"
      }
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = local.env.ecr.keep_images
      }
    }]
  })
  repository_lambda_read_access_arns = each.key == "imgproxy" ? [module.imgproxy.lambda_function_arn] : []
  tags = {
    Name = "${local.project}-images-${each.key}"
  }
}

module "ecr_registry_config" {
  source            = "terraform-aws-modules/ecr/aws"
  version           = "3.1.0"
  create_repository = false
  manage_registry_scanning_configuration = true
  registry_scan_type  = "BASIC"
  registry_scan_rules = [{
    scan_frequency = "SCAN_ON_PUSH"
    filter = [{
      filter      = "*"
      filter_type = "WILDCARD"
    }]
  }]
}
