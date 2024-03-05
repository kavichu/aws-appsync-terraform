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
  alias_attributes         = ["email"]
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

resource "aws_appsync_resolver" "get_tasks_resoulver" {
  api_id = aws_appsync_graphql_api.graphql_api.id
  type   = "Query"
  field  = "getTasks"
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
  code = file("resolvers/getTasks.js")
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
}

resource "aws_lambda_function" "add_task_lambda_function" {
  function_name = "addTaskLambdaFunction"
  filename      = "add_task_lambda_function.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.addTask"
  runtime       = "nodejs20.x"
  timeout = 30
}

resource "aws_lambda_function" "post_confirmation_lambda_function" {
  function_name = "postConfirmationLambdaFunction"
  filename      = "post_confirmation_lambda_function.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.postConfirmation"
  runtime       = "nodejs20.x"
  timeout = 30
}