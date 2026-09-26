# Preserve the existing /boa/valkey/credentials physical Secret while moving
# ownership from the reusable module to the aws-cache root.
moved {
  from = module.elasticache.aws_secretsmanager_secret.valkey
  to   = aws_secretsmanager_secret.valkey_credentials
}

# A managed random_password has no external object to destroy. Remove only its
# obsolete state entry; the replacement ephemeral value is never persisted.
removed {
  from = module.elasticache.random_password.valkey

  lifecycle {
    destroy = false
  }
}

# Secret versions are immutable history. Keep the existing version in AWS and
# create a new write-only AWSCURRENT version instead of planning a replacement.
removed {
  from = module.elasticache.aws_secretsmanager_secret_version.valkey

  lifecycle {
    destroy = false
  }
}

# Changing boa-app to redis requires a new physical ElastiCache user. Forget
# the old address without deleting the physical user, then declaratively import
# it at the migration-only root address. Unlike a direct moved block, this
# re-read does not carry the legacy plaintext password into the new state.
removed {
  from = module.elasticache.aws_elasticache_user.app

  lifecycle {
    destroy = false
  }
}

import {
  to = aws_elasticache_user.valkey_legacy
  id = "boa-app"
}
