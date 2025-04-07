
resource "aws_lambda_function" "postcode_insert_lambda" {
  filename         = data.archive_file.postcode_insert_function.output_path
  function_name    = local.postcode_insert_function_name
  layers           = ["arn:aws:lambda:eu-west-2:336392948345:layer:AWSSDKPandas-Python39:28"]
  description      = local.postcode_insert_description
  role             = aws_iam_role.postcode_insert_lambda_role.arn
  handler          = "postcode_insert.lambda_handler"
  source_code_hash = data.archive_file.postcode_insert_function.output_base64sha256
  runtime          = local.postcode_insert_runtime
  timeout          = local.postcode_insert_timeout
  memory_size      = local.postcode_insert_memory_size
  publish          = false
  tags             = local.standard_tags
  environment {
    variables = {
      SOURCE_BUCKET              = local.postcode_etl_s3_bucket
      DYNAMODB_DESTINATION_TABLE = local.postcode_extract_dynamoDb_destination_table
      INPUT_FOLDER               = local.postcode_etl_s3_source_folder
      PROCESSED_FOLDER           = local.postcode_etl_s3_processed_folder
      LOGGING_LEVEL              = var.postcode_etl_logging_level
    }
  }
  vpc_config {
    subnet_ids         = keys(data.aws_subnet.texas_private_subnet_ids_as_map_of_objects)
    security_group_ids = [aws_security_group.insert_lambda_sg.id]
  }
}

resource "aws_security_group" "insert_lambda_sg" {
  name        = "${var.service_prefix}-insert-lambda-sg"
  description = "Security group for the insert lambda"
  vpc_id      = data.aws_vpc.vpc[0].id

  tags = local.standard_tags
}

resource "aws_security_group_rule" "insert_lambda_egress_443" {
  type              = "egress"
  from_port         = "443"
  to_port           = "443"
  protocol          = "tcp"
  security_group_id = aws_security_group.insert_lambda_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "A rule to allow outgoing connections AWS APIs from the lambda Security Group"
}

resource "aws_iam_role" "postcode_insert_lambda_role" {
  name               = local.postcode_insert_iam_name
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

resource "aws_iam_role_policy" "uec-sf-postcode-insert" {
  name   = local.postcode_insert_policy_name
  role   = aws_iam_role.postcode_insert_lambda_role.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
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

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRoleInsert" {
  role       = aws_iam_role.postcode_insert_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "s3FullAccessInsert" {
  role       = aws_iam_role.postcode_insert_lambda_role.name
  policy_arn = local.s3_full_access_policy_arn
}

resource "aws_iam_role_policy_attachment" "dynamoDbFullAccessInsert" {
  role       = aws_iam_role.postcode_insert_lambda_role.name
  policy_arn = local.dynamoDb_full_access_policy_arn
}
resource "aws_cloudwatch_log_group" "postcode_insert_log_group" {
  name = "/aws/lambda/${aws_lambda_function.postcode_insert_lambda.function_name}"
}
