terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.1"
    }
  }
  backend "s3" {
    key    = "state/terraform.tfstate"
    region = "us-east-1"
  }
}

module "appsync_api" {
  source = "./appsync"
  region = "us-east-1"
}