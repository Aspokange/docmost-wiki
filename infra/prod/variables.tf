variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "server_name" {
  description = "Name of the EC2 instance"
  type        = string
  default     = "docmost-server-prod"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}