terraform {
  required_version = ">= 1.9.0" # cross-variable validation

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.95"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Credentials are read from the environment, never from files in this repo:
#   export CONFLUENT_CLOUD_API_KEY=...
#   export CONFLUENT_CLOUD_API_SECRET=...
# Use a Cloud resource management API key (not a Kafka cluster key).
provider "confluent" {}
