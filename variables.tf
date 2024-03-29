variable "image" {
  type    = string
  default = "cockroachdb/cockroach:v23.2.3"
}

variable "container_cpu" {
  type    = string
  default = null
}

variable "container_memory" {
  type    = string
  default = null
}

variable "replicas" {
  type    = number
  default = 3
}

variable "storage_class" {
  type    = string
  default = null
}

variable "storage_size" {
  type    = string
  default = "10Gi"
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "name" {
  type    = string
  default = "cockroachdb"
}

variable "nodeSelector" {
  type    = map(string)
  default = null
}

variable "client_cert_users" {
  type    = list(string)
  default = ["root"]
}

variable "cert_validity_period_hours" {
  type    = number
  default = 17520
}

variable "cert_early_renewal_hours" {
  type    = number
  default = 8760
}
