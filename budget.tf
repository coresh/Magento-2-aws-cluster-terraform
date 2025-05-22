

/////////////////////////////////////////////////[ AWS BUDGET NOTIFICATION ]//////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create alert when your budget thresholds are forecasted to exceed
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_budgets_budget" "this" {
  name              = "${local.project}-budget-monthly-forecasted"
  budget_type       = "COST"
  limit_amount      = local.env.budget_limit_amount
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  dynamic "notification" {
    for_each = toset(["25", "50", "75", "100", "125", "150"])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_sns_topic_arns  = [module.sns["budget"].topic_arn]
    }
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create alert when your Cost Anomaly Detection trigger changes
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ce_anomaly_monitor" "cost" {
  name              = "${local.project}-cost-anomaly-detection"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags = {
    Name = "${local.project}-cost-anomaly-detection"
    }
}

resource "aws_ce_anomaly_subscription" "cost_alert" {
  name      = "${local.project}-cost-anomaly-alert"
  frequency = "IMMEDIATE"
  threshold_expression {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = ["15"]
      }
    }
  monitor_arn_list = [
    aws_ce_anomaly_monitor.cost.arn
  ]
  subscriber {
    type    = "SNS"
    address = module.sns["budget"].topic_arn
  }
}
