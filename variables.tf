
variable "subscription_id" {
  description = "ID de la suscripción de Azure"
  type        = string
}

variable "location" {
  description = "Región de Azure"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "microservicio"
}

variable "docker_image" {
  description = "Imagen Docker que se desplegará"
  type        = string
}

variable "nombre" {
  description = "Nombre utilizado por el endpoint hello"
  type        = string
  default     = "Estudiante"
}

variable "mi_variable" {
  description = "Variable de entorno del microservicio"
  type        = string
  default     = "Hola desde Azure"
}
