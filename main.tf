terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.1"
    }
  }
  backend "s3" {
    bucket = "appsync-terraform-backend"
    key    = "state/terraform.tfstate"
    region = "us-east-1"
  }
}

module "appsync_api" {
  source = "./modules/appsync"
}