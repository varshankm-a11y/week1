terraform {
  backend "s3" {
    bucket = "PLACEHOLDER_BUCKET"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}
