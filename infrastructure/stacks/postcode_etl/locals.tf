locals {
  service_account_role_name            = "${var.service_prefix}-role"
  postcode_service_account_policy_name = "${var.service_prefix}-policy"
  postcode_insert_function_name        = "${var.service_prefix}-postcode-insert"
  postcode_insert_description          = "Service Finder function to insert postcode and postcode mappings into DynamoDB"
  postcode_insert_runtime              = "python3.9"
  postcode_insert_timeout              = 900
  postcode_insert_memory_size          = 2048

  postcode_extract_function_name = "${var.service_prefix}-postcode-extract"
  postcode_extract_description   = "Service Finder function to extract postcode and postcode mapping from DoS database into csv files"
  postcode_extract_runtime       = "python3.9"
  postcode_extract_timeout       = 900
  postcode_extract_memory_size   = 2048
  # postcode_extract_core_dos_python_libs_arn = data.aws_lambda_layer_version.dos_python_libs.arn

  region_update_function_name = "${var.service_prefix}-region-update"
  region_update_description   = "Service finder function to update postcode mappings with region and subregions"
  region_update_runtime       = "python3.9"
  region_update_timeout       = 900
  region_update_memory_size   = 2048

  email_update_function_name = "${var.service_prefix}-email-update"
  email_update_description   = "Service finder function to update postcode mappings with email and ICBs"
  email_update_runtime       = "python3.9"
  email_update_timeout       = 900
  email_update_memory_size   = 2048

  file_generator_function_name = "${var.service_prefix}-ccg-file-generator"
  file_generator_description   = "Service finder function to generate ccg csv from pcodey files"
  file_generator_runtime       = "python3.9"
  file_generator_timeout       = 900
  file_generator_memory_size   = 2048

  //Environment variables for lambda
  region_update_dynamoDb_destination_table    = var.postcode_mapping_dynamo_name
  postcode_extract_dynamoDb_destination_table = var.postcode_mapping_dynamo_name
  postcode_etl_s3_bucket                      = var.sf_resources_bucket
  postcode_etl_s3_bucket_arn                  = aws_s3_bucket.postcode_etl_s3.arn
  postcode_etl_s3_source_folder               = "postcode_locations/"
  postcode_etl_s3_file_prefix                 = "postcode_extract"
  postcode_etl_s3_processed_folder            = "processed_postcodes/"
  postcode_extract_db_user                    = var.postcode_etl_db_user
  postcode_extract_source_db                  = var.postcode_etl_source_db
  postcode_extract_db_endpoint                = var.sf_read_replica_db
  postcode_extract_db_port                    = "5432"
  postcode_extract_db_region                  = "eu-west-2"
  postcode_extract_db_batch_size              = "50000"
  postcode_extract_db_secret_name             = var.dos_read_replica_secret_name
  postcode_extract_db_key                     = var.dos_read_replica_key
  postcode_extract_db_secret_arn              = data.aws_secretsmanager_secret.dos_read_replica_secret_name.arn

  postcode_insert_iam_name  = "${var.service_prefix}-postcode-insert-lambda"
  region_update_iam_name    = "${var.service_prefix}-region-update-lambda"
  email_update_iam_name     = "${var.service_prefix}-email-update-lambda"
  file_generator_iam_name   = "${var.service_prefix}-file_generator-lambda"
  postcode_extract_iam_name = "${var.service_prefix}-postcode-extract-lambda"

  postcode_extract_policy_name = "${var.service_prefix}-postcode-dos-extract"
  postcode_insert_policy_name  = "${var.service_prefix}-postcode-insert-create-cloudwatch-logs"
  region_update_policy_name    = "${var.service_prefix}-region-update-create-cloudwatch-logs"
  email_update_policy_name     = "${var.service_prefix}-email-update-create-cloudwatch-logs"
  file_generator_policy_name   = "${var.service_prefix}-ccg-file-generator-logs"

  s3_full_access_policy_arn            = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  dynamoDb_full_access_policy_arn      = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  rds_data_read_only_access_policy_arn = "arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"

  postcode_extract_cloudwatch_event_name            = "${var.service_prefix}-postcode-extract-rule"
  postcode_extract_cloudwatch_event_description     = "Daily timer to extract postcode and postcode data out of DoS an into the s3 bucket at 1am"
  postcode_extract_cloudwatch_event_cron_expression = "cron(0 1 ? * * *)"
  postcode_extract_cloudwatch_event_target          = "lambda"
  postcode_extract_cloudwatch_event_statement       = "AllowExecutionFromCloudWatch"
  postcode_extract_cloudwatch_event_action          = "lambda:InvokeFunction"
  postcode_extract_cloudwatch_event_princinple      = "events.amazonaws.com"

  region_update_cloudwatch_event_name            = "${var.service_prefix}-region-update-rule"
  region_update_cloudwatch_event_description     = "task is scheduled to run at 1:00 AM, 2:00 AM, 3:00 AM, and so on, every day."
  region_update_cloudwatch_event_cron_expression = "cron(0 */1 * * ? *)"
  region_update_cloudwatch_event_target          = "lambda"
  region_update_cloudwatch_event_statement       = "AllowExecutionFromCloudWatch"
  region_update_cloudwatch_event_action          = "lambda:InvokeFunction"
  region_update_cloudwatch_event_princinple      = "events.amazonaws.com"

  email_update_cloudwatch_event_name            = "${var.service_prefix}-email-update-rule"
  email_update_cloudwatch_event_description     = "task is scheduled to run at 1:10 AM, 2:10 AM, 3:10 AM, and so on, every day."
  email_update_cloudwatch_event_cron_expression = "cron(10 */1 * * ? *)"
  email_update_cloudwatch_event_target          = "lambda"
  email_update_cloudwatch_event_statement       = "AllowExecutionFromCloudWatch"
  email_update_cloudwatch_event_action          = "lambda:InvokeFunction"
  email_update_cloudwatch_event_princinple      = "events.amazonaws.com"

  step_function_cloudwatch_event_name            = "${var.service_prefix}-step-function-event-rule"
  step_function_cloudwatch_event_description     = "Daily timer to run step function for parallel execution of update lambdas"
  step_function_cloudwatch_event_target          = "states"
  step_function_cloudwatch_event_cron_expression = "cron(0 */1 * * ? *)"
  standard_tags = {
    "Programme"        = "uec"
    "Service"          = "service-finder"
    "Product"          = "service-finder"
    "service_prefixes" = "uec-sf"
    "tag"              = "uec-sf"
    "uc_name"          = "UECSF"
    "Environment"      = var.profile
  }

}
