variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "cluster-name" {
  description = "Name of EKS Cluster"
  default     = ""
}

variable "full-vpc-subnet" {
  description = "Full /16 network"
  default     = ""
}

variable "vpc-second-octet" {
  description = "Second octet of the full subnet"
  default     = ""
}

variable "environment" {
  description = "Environment"
  default     = ""
}
