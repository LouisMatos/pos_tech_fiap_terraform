# Provider OIDC unico para o GitHub Actions assumir roles temporarias em vez
# de usar AWS_ACCESS_KEY_ID/SECRET fixas nos secrets dos repos.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "assume_role" {
  for_each = var.repos

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrito ao repo especifico (qualquer branch/tag daquele repo)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${each.key}:*"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.repos

  name               = "github-actions-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for pair in flatten([
    for repo, cfg in var.repos : [
      for arn in cfg.policy_arns : { key = "${repo}-${arn}", repo = repo, arn = arn }
    ]
  ]) : pair.key => pair }

  role       = aws_iam_role.this[each.value.repo].name
  policy_arn = each.value.arn
}
