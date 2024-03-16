variable "name" {
  description = "The name of the NLB"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC where the NLB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "The IDs of the subnets where the NLB will be created"
  type        = list(string)
}

variable "target_type" {
  description = "The type of target that traffic is routed to"
  type        = string
  default     = "ip"
}

variable "port" {
  description = "The port that the NLB will listen on"
  type        = number
}
