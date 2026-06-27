# Frontend - Gestión de Productos y Usuarios (Java + Nginx)

Frontend estático generado a partir de una aplicación Java (Maven) y servido mediante un servidor web de alto rendimiento Nginx. Este proyecto forma parte de la **Evaluación Parcial N°3 de Introducción a Herramientas DevOps**.

---

## 🏛️ Funcionamiento y Compilación (Multi-stage Docker Build)

El frontend utiliza una arquitectura de construcción multi-etapa (Multi-stage build) para mantener la imagen final lo más liviana posible:

1. **Etapa de Construcción (Builder)**: Usa una imagen de `maven:3.8.8` para compilar el código Java y ejecutar `StaticPageGenerator.java`. Este programa genera la estructura estática (`index.html`, `styles.css`, `script.js`) dentro de una carpeta `/output` inyectando las URLs de los servicios de Backend correspondientes.
2. **Etapa de Servidor (Nginx)**: Toma los archivos resultantes de la carpeta `/output` de la etapa anterior y los copia dentro del directorio `/usr/share/nginx/html` de una imagen liviana `nginx:alpine` expuesta en el puerto `80`.

---

## 🚀 Ejecución Local

### Opción 1: Tradicional (Manual)

1. **Requisitos**: Java 17+ y Maven 3.6+.
2. **Configuración**:
   ```bash
   cp .env.example .env
   ```
   Edite `.env` con las direcciones locales de los Backends (ej. `http://localhost:8081` y `http://localhost:8082`).
3. **Generación**:
   ```bash
   mvn clean compile exec:java
   ```
4. **Visualización**: Abra `output/index.html` en su navegador preferido.

### Opción 2: Con Docker (Individual)

1. **Construir la imagen**:
   ```bash
   docker build -t frontend-app:latest \
     --build-arg BACKEND_USERS_URL=http://localhost:8081 \
     --build-arg BACKEND_PRODUCTS_URL=http://localhost:8082 .
   ```
2. **Ejecutar el contenedor**:
   ```bash
   docker run -d -p 8080:80 frontend-app:latest
   ```
3. Abra `http://localhost:8080` en su navegador.

---

## 🏛️ Arquitectura de Despliegue en AWS (ECS Fargate)

Este Frontend está configurado para desplegarse de manera robusta y escalable en la nube utilizando AWS:

* **AWS ECS Fargate**: Ejecuta el contenedor de Nginx de manera serverless en el puerto `80`.
* **AWS ECR**: Repositorio privado para almacenar las imágenes de contenedor (`eva3-frontend-repo`).
* **Application Load Balancer (ALB) y Enrutamiento por Rutas (Path-Based Routing)**:
  Para evitar problemas de **CORS** y simplificar la gestión de nombres de dominio en producción, la arquitectura recomendada utiliza **un único Application Load Balancer** expuesto en el puerto `80` con reglas de enrutamiento por rutas:
  * Regla 1 (Path `/api/users/*`): Enruta el tráfico hacia el Backend 1 (Node.js) en el puerto `8081`.
  * Regla 2 (Path `/api/products*`): Enruta el tráfico hacia el Backend 2 (Python) en el puerto `8082`.
  * Regla Por Defecto (Path `/*`): Enruta el tráfico hacia el servicio Frontend (Nginx) en el puerto `80`.
* **Importante**: Con esta arquitectura de rutas relativas, las variables `BACKEND_USERS_URL` y `BACKEND_PRODUCTS_URL` en el proceso de compilación del Dockerfile se pueden dejar **vacías** (valor por defecto). De esta forma, el Javascript del navegador enviará las peticiones directamente a `/api/users/...` y `/api/products/...`, resolviéndose contra el mismo Load Balancer automáticamente sin necesidad de pre-configurar DNS absolutos.

---

## 📈 Configuración de Autoscaling (IE3)

Para garantizar la alta disponibilidad y tolerancia a fallos del servidor Nginx ante picos de visitas:
* **Métrica objetivo**: CPU Utilization promedio de las tareas.
* **Umbral de escala (Target Tracking)**: **50%**.
  * **Justificación del umbral**: Un umbral del 50% es ideal para entornos de producción de carga variable. Permite absorber ráfagas repentinas de tráfico de red en el servidor estático Nginx mientras Fargate aprovisiona nuevas tareas (lo cual toma entre 1 y 2 minutos) sin saturar las tareas existentes ni degradar la velocidad de carga de la web.
* **Límites de escala**: Mínimo 1 tarea, Máximo 3 tareas (diseñado para mantener el presupuesto controlado en AWS Academy).

---

## 🔄 Pipeline CI/CD con GitHub Actions (IE4)

El archivo `.github/workflows/deploy.yml` automatiza todo el ciclo de entrega continua (build ➡️ push ➡️ deploy):

1. **Gatillo**: Empujar cambios a las ramas `main` o `master`.
2. **Inicio y autenticación**: Configura credenciales usando `aws-actions/configure-aws-credentials` y Secrets de GitHub.
3. **Login en ECR**: Se loguea al registro privado con `aws-actions/amazon-ecr-login`.
4. **Construcción y etiquetado**: Genera la imagen Docker pasando las variables de URLs como argumentos (`--build-arg`). Etiqueta la imagen con el hash del commit (`github.sha`) y la etiqueta `latest`.
5. **Subida**: Empuja ambas imágenes a Amazon ECR.
6. **Actualización de ECS**: Modifica la definición de tarea (`task-definition.json`) con la nueva imagen y despliega la actualización en ECS actualizando el servicio (`frontend-service`).

### Configuración de GitHub Secrets Necesarios:
* `AWS_ACCESS_KEY_ID`: Credencial temporal de AWS.
* `AWS_SECRET_ACCESS_KEY`: Credencial temporal de AWS.
* `AWS_SESSION_TOKEN`: Token de sesión de AWS Academy (obligatorio en Learner Labs).
* `AWS_REGION`: Región de despliegue (ej. `us-east-1`).
* `BACKEND_USERS_URL` (Opcional): Si no se usa enrutamiento por rutas y se requiere URL absoluta.
* `BACKEND_PRODUCTS_URL` (Opcional): Si no se usa enrutamiento por rutas y se requiere URL absoluta.

---

## 📊 Logs y Monitoreo (IE6)

Los logs de acceso y errores del servidor Nginx se transmiten en tiempo real a **Amazon CloudWatch Logs** mediante el driver `awslogs` configurado en `task-definition.json`.
* **Grupo de Logs**: `/ecs/frontend-service`
* **Prefijo de Logs**: `ecs`
* Esto permite verificar el correcto acceso de los usuarios a la página web y descartar problemas de carga del frontend.
