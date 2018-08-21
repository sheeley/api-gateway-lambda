# # To use a custom domain name you must first register that domain
variable "domain" {
  default = "api.example.com"
}

locals {
  safe_domain = "${replace("${var.domain}", ".", "-")}"
}

resource "aws_route53_zone" "api-example-com" {
  name = "${var.domain}"
}

# This group of resources is slow to create/re-create. don't destroy these if possible.
resource "aws_acm_certificate" "api-example-com" {
  domain_name       = "${var.domain}"
  validation_method = "DNS"
}

resource "aws_route53_record" "api-example-com-cert-validation" {
  name    = "${aws_acm_certificate.api-example-com.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.api-example-com.domain_validation_options.0.resource_record_type}"
  zone_id = "${aws_route53_zone.api-example-com.zone_id}"
  records = ["${aws_acm_certificate.api-example-com.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = "${aws_acm_certificate.api-example-com.arn}"
  validation_record_fqdns = ["${aws_route53_record.api-example-com-cert-validation.fqdn}"]
}

resource "aws_route53_record" "api-example-com" {
  zone_id = "${aws_route53_zone.api-example-com.zone_id}"
  name    = "${var.domain}"
  type    = "A"

  alias {
    name                   = "${aws_api_gateway_domain_name.api-example-com.cloudfront_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.api-example-com.cloudfront_zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_api_gateway_domain_name" "api-example-com" {
  domain_name     = "${var.domain}"
  certificate_arn = "${aws_acm_certificate.api-example-com.id}"
}

# END slow things

variable "lambda_zipfile" {
  default = "main.zip"
}

resource "aws_api_gateway_rest_api" "api-example-com" {
  name = "${var.domain} API"
}

resource "aws_api_gateway_resource" "api-example-com-proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.api-example-com.id}"
  parent_id   = "${aws_api_gateway_rest_api.api-example-com.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "api-example-com-proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.api-example-com.id}"
  resource_id   = "${aws_api_gateway_resource.api-example-com-proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_deployment" "api-example-com" {
  rest_api_id = "${aws_api_gateway_rest_api.api-example-com.id}"
  stage_name  = "live"

  depends_on = [
    "aws_api_gateway_integration.api-example-com-lambda",
  ]
}

resource "aws_api_gateway_method_settings" "api-example-com" {
  rest_api_id = "${aws_api_gateway_rest_api.api-example-com.id}"
  stage_name  = "${aws_api_gateway_deployment.api-example-com.stage_name}"
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }

  depends_on = ["aws_api_gateway_account.global-settings"]
}

resource "aws_lambda_function" "api-example-com" {
  function_name    = "${local.safe_domain}-handler"
  filename         = "${var.lambda_zipfile}"
  source_code_hash = "${base64sha256(file("${var.lambda_zipfile}"))}"
  handler          = "main"
  runtime          = "go1.x"
  role             = "${aws_iam_role.api-example-com-lambda-exec.arn}"
}

resource "aws_lambda_permission" "allow-api-gateway" {
  function_name = "${aws_lambda_function.api-example-com.function_name}"
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api-example-com.execution_arn}/${aws_api_gateway_deployment.api-example-com.stage_name}/*/*"
  depends_on    = ["aws_api_gateway_rest_api.api-example-com", "aws_api_gateway_resource.api-example-com-proxy"]
}

resource "aws_lambda_permission" "allow-api-gateway-base" {
  function_name = "${aws_lambda_function.api-example-com.function_name}"
  statement_id  = "AllowExecutionFromApiGatewayBase"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api-example-com.execution_arn}/${aws_api_gateway_deployment.api-example-com.stage_name}"
  depends_on    = ["aws_api_gateway_rest_api.api-example-com", "aws_api_gateway_resource.api-example-com-proxy"]
}

# IAM role which dictates what other AWS services the Lambda function
# may access.
resource "aws_iam_role" "api-example-com-lambda-exec" {
  name = "${local.safe_domain}-lamdba"

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

resource "aws_iam_role_policy_attachment" "api-example-com-lambda-logs" {
  role       = "${aws_iam_role.api-example-com-lambda-exec.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}

resource "aws_api_gateway_integration" "api-example-com-lambda" {
  rest_api_id             = "${aws_api_gateway_rest_api.api-example-com.id}"
  resource_id             = "${aws_api_gateway_method.api-example-com-proxy.resource_id}"
  http_method             = "${aws_api_gateway_method.api-example-com-proxy.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.api-example-com.invoke_arn}"
}

resource "aws_api_gateway_base_path_mapping" "api-example-com" {
  api_id      = "${aws_api_gateway_rest_api.api-example-com.id}"
  stage_name  = "${aws_api_gateway_deployment.api-example-com.stage_name}"
  domain_name = "${aws_api_gateway_domain_name.api-example-com.domain_name}"
}
