terraform {
  backend "s3" {
    bucket = "sctp-tfstate-ce13"
    key    = "tk\tf-coaching17-infrap-github-iam-boostrap.tfstate"
    #use_lockfile = true
    region = "us-east-1"
  }
}