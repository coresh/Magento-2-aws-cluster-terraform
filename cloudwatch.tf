

/////////////////////////////////////////////////////[ CLOUDWATCH ALARMS ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create CloudWatch Utilization metrics and email alerts
# # ---------------------------------------------------------------------------------------------------------------------#
module "metric_alarm" {
  source              = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version             = "5.7.1"
  for_each            = local.metrics_alarm
  alarm_name          = "${local.project}-${each.value.namespace}-${each.key}-${each.value.metric_name}"
  alarm_description   = "${each.value.namespace} ${each.key} ${each.value.metric_name} utilization"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  period              = each.value.period
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  alarm_actions       = [module.sns["devops"].topic_arn]
  ok_actions                = [module.sns["devops"].topic_arn]
  insufficient_data_actions = [module.sns["devops"].topic_arn]
  dimensions = each.value.dimensions != "" ? {
    (each.value.dimensions) = lookup({
      "AutoScalingGroupName" = module.autoscaling["backend"].autoscaling_group_name
      "LoadBalancer"         = module.alb.id
    }, each.value.dimensions, null)
    } : null
}
