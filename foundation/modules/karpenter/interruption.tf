# Interruption handling.
#
# Karpenter learns that an instance is going away by reading events from an SQS
# queue that EventBridge feeds. Without this, a Spot reclaim gives the cluster no
# warning: the node vanishes and its pods are killed rather than drained. Karpenter
# runs fine without the queue — which is exactly the trap, since the gap only shows
# up during an interruption, when it is too late to notice.
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.project_name}-karpenter-interruption"
  message_retention_seconds = 300 # events are only useful for the ~2 min of notice
  sqs_managed_sse_enabled   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-karpenter-interruption"
    }
  )
}

# Only EventBridge may publish here, and only on behalf of this account.
data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

# The four event types Karpenter acts on. Spot interruption is the famous one, but
# a rebalance recommendation arrives earlier, and health/state-change events cover
# the non-Spot cases.
locals {
  interruption_events = {
    spot_interruption = {
      description = "EC2 Spot instance interruption warning"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      description = "EC2 instance rebalance recommendation"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance Rebalance Recommendation"]
    }
    state_change = {
      description = "EC2 instance state change"
      source      = ["aws.ec2"]
      detail_type = ["EC2 Instance State-change Notification"]
    }
    scheduled_change = {
      description = "AWS health event scheduling a change"
      source      = ["aws.health"]
      detail_type = ["AWS Health Event"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name        = "${var.project_name}-karpenter-${each.key}"
  description = each.value.description

  event_pattern = jsonencode({
    source        = each.value.source
    "detail-type" = each.value.detail_type
  })

  tags = var.tags
}

# Keyed on the static map, not on the rules resource.
#
# `for_each = aws_cloudwatch_event_rule.interruption` reads naturally and breaks
# whenever the rules do not already exist: Terraform cannot know the map's keys
# until apply, and refuses to plan at all —
#
#   Invalid for_each argument … will be known only after apply
#
# It never surfaced during a normal apply, because the rules are created before
# anything reads them. It surfaced the first time someone ran `terraform import`
# against a state where the rules had been destroyed, and it took the whole
# module with it: import, plan and apply all fail the same way, on a resource
# that has nothing to do with what is being imported.
#
# local.interruption_events is a literal, so its keys are known at plan time
# regardless of what exists. The rules are then indexed by that key.
resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule = aws_cloudwatch_event_rule.interruption[each.key].name
  arn  = aws_sqs_queue.interruption.arn
}
