# The EC2 Spot service-linked role. One per account, created once, which is why it
# is here and not in foundation: destroying an environment must not delete it.
#
# EC2 creates it on the first Spot request — when the caller may create it. Karpenter's
# role may not (iam:CreateServiceLinkedRole is deliberately not granted), so without
# this every Spot launch failed with AuthFailure.ServiceLinkedRoleCreationNotPermitted
# and the NodePool's on-demand fallback hid it: nodes arrived, only never as Spot.
#
# In an account that already has the role, import it instead of applying:
#   terraform -chdir=bootstrap import aws_iam_service_linked_role.spot \
#     arn:aws:iam::<account>:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot
resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "EC2 Spot, for Karpenter's Spot capacity"
}
