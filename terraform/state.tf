data "terraform_remote_state" "apps" {
  backend = "s3"

  config = {
    bucket = "bootcamperu-tf-state"
    key    = "bootcamperu.tfstate"
    region = "us-east-1"
  }
}
