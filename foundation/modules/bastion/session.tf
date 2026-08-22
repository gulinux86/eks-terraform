# Session Manager preferences.
#
# By default a session starts a plain, non-login shell — the prompt gives it away
# (`sh-5.2$`). A non-login shell never reads /etc/profile, and therefore never
# reads /etc/profile.d/*.sh, so anything placed there (KUBECONFIG, completion) is
# silently ignored. The boot script was writing the file correctly; the session was
# simply never looking at it.
#
# `bash -l` makes the session a login shell, which restores the standard Linux
# mechanism: whatever lands in /etc/profile.d applies, now and for anything added
# later. It also gives an interactive bash instead of sh — completion works, and
# the prompt is legible.
#
# SCOPE WARNING: this document name is account-wide. One account can hold exactly
# one `SSM-SessionManagerRunShell`, so two environments sharing an account would
# fight over it. That is fine while environments are separate accounts (the
# intended design), and the flag below exists for when they are not.
resource "aws_ssm_document" "session_shell" {
  count = var.manage_ssm_session_shell ? 1 : 0

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences — login shell so /etc/profile.d applies"
    sessionType   = "Standard_Stream"
    inputs = {
      # No S3/CloudWatch session logging yet; it belongs with the observability
      # work, where something would actually read it.
      runAsEnabled       = false
      shellProfile       = { linux = "bash -l" }
      idleSessionTimeout = "60"
    }
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-session-shell"
    }
  )
}
