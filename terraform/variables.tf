variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
  default     = "voting-app"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# --- Container image URIs (push to ECR and update these) ---
variable "vote_image" {
  description = "Docker image URI for the vote service"
  type        = string
  default     = "dockersamples/examplevotingapp_vote:latest"
}

variable "result_image" {
  description = "Docker image URI for the result service"
  type        = string
  default     = "dockersamples/examplevotingapp_result:latest"
}

variable "worker_image" {
  description = "Docker image URI for the worker service"
  type        = string
  default     = "dockersamples/examplevotingapp_worker:latest"
}

# --- Database ---
variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "postgres"
}

variable "db_username" {
  description = "Postgres master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Postgres master password"
  type        = string
  sensitive   = true
  default     = "changeme123!"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# --- ElastiCache ---
variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}
