resource "aws_dynamodb_table" "tasks_table" {
  name         = "TasksTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "owner"
    type = "S"
  }

  global_secondary_index {
    name            = "byOwner"
    hash_key        = "owner"
    range_key       = "id"
    projection_type = "ALL"
  }

}

resource "aws_dynamodb_table" "users_table" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

}

resource "aws_cognito_user_pool" "user_pool" {
  name                     = "UserPool"
  username_attributes = [ "email" ]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_uppercase = false
    require_numbers   = false
    require_symbols   = false
  }
  admin_create_user_config {
    allow_admin_create_user_only = false # enable self sign in
  }
  lambda_config {
    post_confirmation = aws_lambda_function.post_confirmation_lambda_function.arn
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "UserPoolClient"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_appsync_graphql_api" "graphql_api" {
  name = "terraform-todos-api"

  schema = file("schema.graphql")

  visibility = "GLOBAL"

  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config {
    default_action      = "ALLOW"
    user_pool_id        = aws_cognito_user_pool.user_pool.id
    app_id_client_regex = aws_cognito_user_pool_client.user_pool_client.id
  }

}

resource "aws_iam_role" "appsync_datasource_role" {
  name = "appsync_datasource_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name = "appsync_inline"
    policy = data.aws_iam_policy_document.appsync_inline_policy.json
  }
  inline_policy {
    name = "appsync_invoke_lambda_inline"
    policy = data.aws_iam_policy_document.appsync_invoke_lambda_inline_policy.json
  }
}

data "aws_iam_policy_document" "appsync_inline_policy" {
  statement {
    actions   = ["dynamodb:Query"]
    resources = [
      "${aws_dynamodb_table.tasks_table.arn}/index/byOwner"
    ]
  }
}

data "aws_iam_policy_document" "appsync_invoke_lambda_inline_policy" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.add_task_lambda_function.arn
    ]
  }
}

resource "aws_appsync_datasource" "tasks_table_datasource" {
  api_id           = aws_appsync_graphql_api.graphql_api.id
  name             = "TasksTableDataSource"
  type             = "AMAZON_DYNAMODB"
  service_role_arn = aws_iam_role.appsync_datasource_role.arn
  dynamodb_config {
    table_name = aws_dynamodb_table.tasks_table.name
    region     = "us-east-1"
  }
}

resource "aws_appsync_resolver" "get_tasks_resolver" {
  api_id = aws_appsync_graphql_api.graphql_api.id
  type   = "Query"
  field  = "getTasks"
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
  code = file("resolvers/getTasks.js")
  data_source = aws_appsync_datasource.tasks_table_datasource.name
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  inline_policy {
    name = "lambda_inline"
    policy = data.aws_iam_policy_document.lambda_inline_policy.json
  }
}

data "aws_iam_policy_document" "lambda_inline_policy" {
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [
      aws_dynamodb_table.tasks_table.arn,
      aws_dynamodb_table.users_table.arn
    ]
  }
}

resource "aws_lambda_function" "add_task_lambda_function" {
  function_name = "addTaskLambdaFunction"
  filename      = "add_task_lambda_function.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.addTask"
  runtime       = "nodejs20.x"
  timeout = 30
  environment {
    variables = {
      TASKS_TABLE = aws_dynamodb_table.tasks_table.name
    }
  }
}

resource "aws_appsync_datasource" "add_task_datasource" {
  api_id           = aws_appsync_graphql_api.graphql_api.id
  name             = "AddTaskDataSource"
  type             = "AWS_LAMBDA"
  service_role_arn = aws_iam_role.appsync_datasource_role.arn
  lambda_config {
    function_arn = aws_lambda_function.add_task_lambda_function.arn
  }
}

resource "aws_appsync_resolver" "add_task_resolver" {
  api_id = aws_appsync_graphql_api.graphql_api.id
  type   = "Mutation"
  field  = "addTask"
  data_source = aws_appsync_datasource.add_task_datasource.name
}

resource "aws_lambda_function" "post_confirmation_lambda_function" {
  function_name = "postConfirmationLambdaFunction"
  filename      = "post_confirmation_lambda_function.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.postConfirmation"
  runtime       = "nodejs20.x"
  timeout = 30
  environment {
    variables = {
      USERS_TABLE = aws_dynamodb_table.users_table.name
    }
  }
}

resource "aws_lambda_permission" "allow_cognito" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation_lambda_function.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.user_pool.arn
}

module "application_user_pool_id" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  name  = "/Application/UserPoolId"
  value = aws_cognito_user_pool.user_pool.id
}

module "application_user_pool_client_id" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  name  = "/Application/UserPoolClientId"
  value = aws_cognito_user_pool_client.user_pool_client.id
}

module "application_graphql_endpoint" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  name  = "/Application/GraphQLEndpointUrl"
  value = aws_appsync_graphql_api.graphql_api.uris["GRAPHQL"]
}
