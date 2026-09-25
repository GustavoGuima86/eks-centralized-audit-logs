# Example spoke accounts only — replace these reserved example IDs and names
# with your real cluster/account values before applying.
spoke_clusters = {
  example_dev_cluster = {
    spoke_account_id   = "111122223333"
    enable_object_lock = false
    expiration_days    = 180
  }

  example_prod_cluster = {
    spoke_account_id           = "444455556666"
    enable_object_lock         = true
    object_lock_retention_days = 3650
  }
}

aws_region   = "us-east-1"
alert_target = "none"
