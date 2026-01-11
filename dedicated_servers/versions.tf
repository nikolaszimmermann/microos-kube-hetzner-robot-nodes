terraform {
  required_version = ">= 1.8.6"

  required_providers {
    hrobot = {
      source  = "midwork-finds-jobs/hrobot"
      version = "~> 0.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}
