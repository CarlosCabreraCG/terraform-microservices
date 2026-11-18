# Infraestructura Azure — Terraform

Este repositorio aprovisiona la infraestructura cloud para desplegar el microservicio NestJS en **Azure Container Apps**. La infraestructura se define como código mediante Terraform.

## Recursos aprovisionados

| Recurso Terraform | Propósito |
|---|---|
| `azurerm_resource_group.rg` | Agrupa los recursos del proyecto. |
| `azurerm_log_analytics_workspace.logs` | Recibe y conserva los logs del entorno. |
| `azurerm_container_app_environment.environment` | Entorno administrado para Azure Container Apps, integrado con Log Analytics. |
| `azurerm_user_assigned_identity.app_identity` | Identidad administrada asignada a la aplicación. |
| `azurerm_container_app.app` | Ejecuta la imagen Docker de NestJS y expone el ingreso HTTPS. |
| `azurerm_key_vault.kv` | Almacena secretos. Utiliza autorización RBAC. |
| `azurerm_storage_account.storage` | Cuenta de almacenamiento para blobs. |
| `azurerm_storage_container.images` | Contenedor privado `imagenes`. |
| `azurerm_role_assignment.kv_access` | Concede a la identidad de la aplicación `Key Vault Secrets User`. |
| `azurerm_role_assignment.storage_access` | Concede a la identidad de la aplicación `Storage Blob Data Reader`. |
| `azurerm_role_assignment.user_kv_access` | Concede al usuario que ejecuta Terraform `Key Vault Secrets Officer`. |
| `azurerm_role_assignment.user_storage_access` | Concede al usuario que ejecuta Terraform `Storage Blob Data Contributor`. |
| `random_string.suffix` | Genera un sufijo para reducir conflictos de nombres globales. |
| `data.azurerm_client_config.current` | Obtiene los datos del tenant y del usuario/identidad que ejecuta Terraform. |

## Diagrama lógico

```text
                         Usuario / Cliente
                                |
                             HTTPS
                                |
                     Azure Container Apps
                                |
                         Microservicio
                            NestJS
                                |
                    User Assigned Managed Identity
                         /                 \
                        /                   \
               Azure Key Vault       Azure Blob Storage
               (secretos)             (contenedor privado)
```

La identidad administrada permite que la aplicación se autentique contra los servicios de Azure sin almacenar claves de acceso en el código o en la imagen Docker.

## Configuración

Requisitos:

- Terraform instalado.
- Azure CLI instalado.
- Suscripción de Azure.
- Permisos para crear recursos y asignaciones RBAC en la suscripción/grupo de recursos.
- Una imagen Docker accesible por Azure Container Apps (por ejemplo, una imagen pública de Docker Hub).

Inicia sesión:

```bash
az login
az account set --subscription "ID_O_NOMBRE_DE_LA_SUSCRIPCION"
```

Revisa la suscripción activa:

```bash
az account show --output table
```

Define los valores de las variables en `terraform.tfvars`. Ejemplo orientativo (los nombres deben coincidir con `variables.tf` del proyecto):

```hcl
project_name = "micronest"
location     = "eastus"
nombre       = "Tu Nombre"
mi_variable  = "Valor de prueba"
docker_image = "USUARIO_DOCKERHUB/terraform-docker-nestjs:latest"
```

`project_name` debe producir nombres válidos para los servicios de Azure. En particular, el nombre del Storage Account debe cumplir las reglas de Azure: entre 3 y 24 caracteres, solo letras minúsculas y números, y ser globalmente único. El nombre de Key Vault también debe ser único y cumplir sus reglas de nomenclatura.

No incluyas secretos, contraseñas, tokens ni credenciales en `terraform.tfvars`. Este archivo debe estar ignorado por Git si contiene valores específicos del entorno.

## Inicializar y desplegar

Desde la carpeta de este repositorio:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Para revisar los recursos creados, se pueden consultar los outputs:

```bash
terraform output
```

## Outputs

El proyecto expone estos outputs:

| Output | Descripción |
|---|---|
| `resource_group_name` | Nombre del grupo de recursos. |
| `container_app_name` | Nombre de Azure Container App. |
| `container_app_url` | URL HTTPS pública de la aplicación. |
| `key_vault_name` | Nombre del Key Vault. |
| `key_vault_uri` | URI del Key Vault. |
| `storage_account_name` | Nombre del Storage Account. |
| `storage_container_name` | Nombre del contenedor de blobs. |

Ejemplos:

```bash
terraform output -raw container_app_url
terraform output -raw key_vault_name
terraform output -raw storage_account_name
```

## Configuración de Key Vault

El Key Vault utiliza RBAC (`rbac_authorization_enabled = true`).

La identidad administrada de la Container App recibe:

- `Key Vault Secrets User`: puede leer secretos.

El usuario que ejecuta Terraform recibe:

- `Key Vault Secrets Officer`: puede administrar secretos.

Después de desplegar la infraestructura, crea el secreto requerido por la aplicación:

```bash
az keyvault secret set \
  --vault-name "$(terraform output -raw key_vault_name)" \
  --name "mensaje-secreto" \
  --value "CAMBIA_ESTO_POR_UN_VALOR_DE_PRUEBA"
```

Comprueba los nombres de secretos sin imprimir sus valores:

```bash
az keyvault secret list \
  --vault-name "$(terraform output -raw key_vault_name)" \
  --query "[].name" \
  --output table
```

Las asignaciones RBAC pueden tardar unos minutos en propagarse.

## Configuración de Blob Storage

Terraform crea:

- Un Storage Account `StorageV2`, Standard, con replicación LRS.
- Un contenedor llamado `imagenes`.
- Acceso privado al contenedor (`container_access_type = "private"`).

La identidad administrada de la Container App recibe `Storage Blob Data Reader`, que permite leer blobs. El usuario que ejecuta Terraform recibe `Storage Blob Data Contributor`, que permite cargar y administrar blobs.

Ejemplo para cargar una imagen:

```bash
az storage blob upload \
  --account-name "$(terraform output -raw storage_account_name)" \
  --container-name "$(terraform output -raw storage_container_name)" \
  --name "imagen.jpg" \
  --file "./imagen.jpg" \
  --auth-mode login
```

Lista los blobs:

```bash
az storage blob list \
  --account-name "$(terraform output -raw storage_account_name)" \
  --container-name "$(terraform output -raw storage_container_name)" \
  --auth-mode login \
  --query "[].name" \
  --output table
```

La aplicación NestJS utiliza las variables de entorno `AZURE_STORAGE_ACCOUNT_NAME`, `AZURE_STORAGE_CONTAINER_NAME` y `AZURE_STORAGE_BLOB_NAME` para localizar el archivo. El blob no necesita ser público: NestJS lo descarga con su identidad administrada y devuelve el contenido desde el endpoint `/imagen`.

## Azure Container Apps

La Container App:

- Ejecuta la imagen indicada por `docker_image`.
- Usa una identidad administrada asignada por el usuario.
- Tiene ingreso externo habilitado por HTTPS.
- Escucha en el puerto objetivo `3000`.
- Está configurada con `revision_mode = "Single"`.
- Tiene `min_replicas = 0` y `max_replicas = 3`.
- Incluye una regla HTTP de escalado con `concurrent_requests = "10"`.

La aplicación recibe variables de entorno para el nombre, la variable de prueba, Key Vault, Storage Account, contenedor y client ID de la identidad.

La configuración de escalado permite ajustar el número de réplicas según la carga; `min_replicas = 0` permite escalar a cero cuando no hay solicitudes, sujeto al comportamiento de Azure Container Apps.

## Actualizar la imagen de la aplicación

Terraform puede actualizar `docker_image` desde `terraform.tfvars` y aplicar el cambio:

```bash
terraform plan
terraform apply
```

También se puede actualizar una Container App existente mediante Azure CLI, por ejemplo desde el script del repositorio NestJS:

```bash
az containerapp update \
  --name "$(terraform output -raw container_app_name)" \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --image "USUARIO_DOCKERHUB/terraform-docker-nestjs:ETIQUETA"
```

El script de despliegue actualiza una aplicación ya creada; no sustituye el aprovisionamiento inicial con Terraform. Mantén Terraform como fuente de verdad de la infraestructura para evitar diferencias entre el estado declarado y los cambios manuales.

## Logs y diagnóstico

Consulta los logs de la aplicación:

```bash
az containerapp logs show \
  --name "$(terraform output -raw container_app_name)" \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --follow
```

Consulta el estado y la revisión:

```bash
az containerapp show \
  --name "$(terraform output -raw container_app_name)" \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --query "properties.latestRevisionName" \
  --output tsv
```

Si una lectura de Key Vault o Blob Storage falla, comprueba:

1. Que la identidad administrada esté asociada a la Container App.
2. Que los roles RBAC estén asignados al `principal_id` correcto.
3. Que haya transcurrido el tiempo de propagación de RBAC.
4. Que las variables de entorno contengan los nombres y URI correctos.
5. Que el secreto o blob exista.
6. Que el nombre del blob y el contenedor coincidan exactamente.

## Seguridad y archivos ignorados por Git

No se deben versionar:

- `.terraform/`
- `*.tfstate` y `*.tfstate.*`
- `*.tfvars` con configuración local o sensible
- `*.tfplan`
- archivos de override locales
- credenciales y archivos `.env`

Ejemplo de `.gitignore`:

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
crash.log
crash.*.log
*.tfvars
!terraform.tfvars.example
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Credenciales y secretos
.env
.env.*
!.env.example
*.pem
*.key
```

El archivo de estado de Terraform puede contener datos sensibles. Para trabajo colaborativo, considera configurar un backend remoto con controles de acceso, bloqueo y cifrado. No subas el estado al repositorio.

## Limpieza de recursos

Para eliminar los recursos administrados por este proyecto:

```bash
terraform destroy
```

Revisa cuidadosamente el plan antes de confirmar. La eliminación del Key Vault puede estar sujeta a las políticas de soft delete y purge protection configuradas en el recurso.

## Alcance actual

La infraestructura incluye Container Apps, Log Analytics, Managed Identity, Key Vault y Blob Storage. La base de datos y el endpoint `/consulta` no están incluidos porque son opcionales en el alcance actual.
