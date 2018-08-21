# api-gateway-lambda
Terraform &amp; Go Lambda fronted by API Gateway

Example code to create an API Gateway endpoint that calls a lambda for any request under the `/` path.

`deploy` handles building the go binary and applying terraform changes.

To use, you should be able to simply modify the `domain` variable - you may want to do a search and replace for `api-example-com` if you want to have properly named resources.