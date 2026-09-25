# Registers this cluster's S3 location as a Glue Catalog table so Athena can
# query its Kubernetes audit event JSON on demand. Kubernetes audit events
# are newline-delimited JSON objects (see processor_lambda), so we use the
# OpenX JSON SerDe with a partition-friendly S3 location matching the
# processor's output layout (cluster/year/month/day/hour). The raw Firehose
# deliveries live in the separate ephemeral raw bucket and are not part of
# this table.

resource "aws_glue_catalog_table" "audit_logs" {
  name          = replace(local.base_name, "-", "_")
  database_name = var.glue_database_name
  description   = "Kubernetes API server audit logs for cluster ${var.cluster_name}"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                    = "TRUE"
    "classification"            = "json"
    "compressionType"           = "gzip"
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2100"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "1,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "1,31"
    "projection.day.digits"     = "2"
    "projection.hour.type"      = "integer"
    "projection.hour.range"     = "0,23"
    "projection.hour.digits"    = "2"
    "storage.location.template" = "s3://${aws_s3_bucket.audit_logs.bucket}/cluster=${var.cluster_name}/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.audit_logs.bucket}/cluster=${var.cluster_name}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "audit-logs-json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "ignore.malformed.json" = "true"
        "case.insensitive"      = "true"
      }
    }

    columns {
      name = "kind"
      type = "string"
    }

    columns {
      name = "apiversion"
      type = "string"
    }

    columns {
      name = "level"
      type = "string"
    }

    columns {
      name = "auditid"
      type = "string"
    }

    columns {
      name = "stage"
      type = "string"
    }

    columns {
      name = "requesturi"
      type = "string"
    }

    columns {
      name = "verb"
      type = "string"
    }

    columns {
      name = "user"
      type = "struct<username:string,groups:array<string>>"
    }

    columns {
      name = "sourceips"
      type = "array<string>"
    }

    columns {
      name = "userAgent"
      type = "string"
    }

    columns {
      name = "objectref"
      type = "struct<resource:string,namespace:string,name:string,apiversion:string>"
    }

    columns {
      name = "responsestatus"
      type = "struct<metadata:string,code:int>"
    }

    columns {
      name = "requestreceivedtimestamp"
      type = "string"
    }

    columns {
      name = "stagetimestamp"
      type = "string"
    }

    columns {
      name = "annotations"
      type = "map<string,string>"
    }
  }
}
