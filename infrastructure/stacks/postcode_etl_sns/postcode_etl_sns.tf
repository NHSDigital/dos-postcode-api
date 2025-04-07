resource "aws_sns_topic" "postcode_etl_sns_topic" {
  name = local.postcode_etl_sns_name
}

resource "aws_sns_topic_subscription" "postcode_etl_sns_subscription" {
  topic_arn = aws_sns_topic.postcode_etl_sns_topic.arn
  protocol  = "email"
  endpoint  = var.postcode_etl_sns_email
}

resource "aws_iam_role" "postcode_etl_sns_role" {
  name               = local.postcode_etl_sns_name
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "uec-postcode_etl_sns_role_policy" {
  name   = local.postcode_etl_sns_policy_name
  role   = aws_iam_role.postcode_etl_sns_role.name
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sns:Publish",
            "Resource": "${aws_sns_topic.postcode_etl_sns_topic.arn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRoleForSns" {
  role       = aws_iam_role.postcode_etl_sns_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "postcode_etl_sns_lambda" {
  filename         = data.archive_file.postcode_etl_sns_function.output_path
  function_name    = local.postcode_etl_sns_name
  description      = local.postcode_etl_sns_description
  role             = aws_iam_role.postcode_etl_sns_role.arn
  handler          = "postcode_etl_sns.lambda_handler"
  source_code_hash = data.archive_file.postcode_etl_sns_function.output_base64sha256
  runtime          = "python3.9"
  publish          = false
  tags             = local.standard_tags
  environment {
    variables = {
      snsARN        = aws_sns_topic.postcode_etl_sns_topic.arn
      LOGGING_LEVEL = local.postcode_etl_sns_logging_level
    }
  }
  vpc_config {
    subnet_ids = keys(data.aws_subnet.texas_private_subnet_ids_as_map_of_objects)
    security_group_ids = [
      aws_security_group.sns_lambda_sg.id
    ]
  }
}

resource "aws_security_group" "sns_lambda_sg" {
  name        = "${var.service_prefix}-sns-lambda-sg"
  description = "Security group for the SNS lambda"
  vpc_id      = data.aws_vpc.vpc[0].id

  tags = local.standard_tags
}

resource "aws_security_group_rule" "sns_lambda_egress_443" {
  type              = "egress"
  from_port         = "443"
  to_port           = "443"
  protocol          = "tcp"
  security_group_id = aws_security_group.sns_lambda_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "A rule to allow outgoing connections AWS APIs from the  lambda Security Group"
}

resource "aws_lambda_permission" "allow_cloudwatch_extract" {
  count = length(data.aws_cloudwatch_log_groups.extract_log_groups) > 0 ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchExtract"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.postcode_etl_sns_lambda.function_name
  principal     = "logs.${var.aws_region}.amazonaws.com"
  source_arn    = data.aws_cloudwatch_log_group.postcode_etl_extract_log_group[0].arn
}

resource "aws_cloudwatch_log_subscription_filter" "postcode_etl_extract_sns_cloudwatch_log_trigger" {
  count = length(data.aws_cloudwatch_log_groups.extract_log_groups) > 0 ? 1 : 0

  depends_on      = [aws_lambda_permission.allow_cloudwatch_extract]
  name            = local.postcode_etl_sns_cloudwatch_event_name
  log_group_name  = data.aws_cloudwatch_log_group.postcode_etl_extract_log_group[0].name
  filter_pattern  = "?ERROR ?WARN ?5xx"
  destination_arn = aws_lambda_function.postcode_etl_sns_lambda.arn
}

# resource "aws_lambda_permission" "allow_cloudwatch_insert" {
#   count = length(data.aws_cloudwatch_log_groups.insert_log_groups) > 0 ? 1 : 0

#   statement_id  = "AllowExecutionFromCloudWatchInsert"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.postcode_etl_sns_lambda.function_name
#   principal     = "logs.${var.aws_region}.amazonaws.com"
#   source_arn    = data.aws_cloudwatch_log_group.postcode_etl_insert_log_group[0].arn
# }

# resource "aws_cloudwatch_log_subscription_filter" "postcode_etl_insert_sns_cloudwatch_log_trigger" {
#   count = length(data.aws_cloudwatch_log_groups.insert_log_groups) > 0 ? 1 : 0

#   depends_on      = [aws_lambda_permission.allow_cloudwatch_insert]
#   name            = local.postcode_etl_sns_cloudwatch_event_name
#   log_group_name  = data.aws_cloudwatch_log_group.postcode_etl_insert_log_group[0].name
#   filter_pattern  = "?ERROR ?WARN ?5xx"
#   destination_arn = aws_lambda_function.postcode_etl_sns_lambda.arn
# }

resource "aws_cloudwatch_metric_alarm" "postcode_extract_alarm" {
  alarm_name                = local.postcode_etl_extract_alarm_name
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "Invocations"
  namespace                 = "AWS/Lambda"
  period                    = var.postcode_etl_extract_alarm_period
  statistic                 = "Average"
  threshold                 = "1"
  alarm_description         = "This metric monitors the postcode extract lambda and sends an alert to a slack channel if it hasnt triggered in the given period"
  insufficient_data_actions = []
  alarm_actions             = [aws_sns_topic.postcode_etl_sns_topic.arn]
  dimensions = {
    FunctionName = local.postcode_extract_function_name
  }

  tags = local.standard_tags
}

# resource "aws_cloudwatch_metric_alarm" "postcode_insert_alarm" {
#   alarm_name                = local.postcode_etl_insert_alarm_name
#   comparison_operator       = "LessThanThreshold"
#   evaluation_periods        = "1"
#   metric_name               = "Invocations"
#   namespace                 = "AWS/Lambda"
#   period                    = var.postcode_etl_insert_alarm_period
#   statistic                 = "Average"
#   threshold                 = "1"
#   alarm_description         = "This metric monitors the postcode insert lambda and sends an alert to a slack channel if it hasnt triggered in the given period"
#   insufficient_data_actions = []
#   alarm_actions             = [aws_sns_topic.postcode_etl_sns_topic.arn]
#   dimensions = {
#     FunctionName = local.postcode_insert_function_name
#   }

#   tags = local.standard_tags
# }
