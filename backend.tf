terraform {
  backend "s3" {
    bucket = "mytfs3bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
