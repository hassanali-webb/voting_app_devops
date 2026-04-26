terraform {
  backend "s3" {
    bucket         = "hassanali-terraform-state-bucket"
    key            = "voting-app/terraform.tfstate"
    region         = "us-east-2"
    # dynamodb_table = "terraform-locks" # Temporarily disabled to resolve state lock conflict
    encrypt        = true
  }
}
