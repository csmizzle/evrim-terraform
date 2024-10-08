variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks"
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}


variable "azs" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}


variable "evrim-domain" {
  type        = string
  description = "Domain Name"
  default     = "evrim.ai"
}

variable "evrim-api-domain" {
  type        = string
  description = "API Domain Name"
  default     = "api.evrim.ai"
}

variable "evrim-ui-domain" {
  type        = string
  description = "UI Domain Name"
  default     = "app.evrim.ai"

}