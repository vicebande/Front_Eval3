# Stage 1: Build the static files
FROM maven:3.8.8-eclipse-temurin-17 AS builder
WORKDIR /app

# Copy pom.xml and source code
COPY pom.xml .
COPY src ./src

# Set build arguments for backend URLs (defaults to empty for relative paths / path-based routing)
ARG BACKEND_USERS_URL=""
ARG BACKEND_PRODUCTS_URL=""

# Set env variables during build so StaticPageGenerator reads them
ENV BACKEND_USERS_URL=${BACKEND_USERS_URL}
ENV BACKEND_PRODUCTS_URL=${BACKEND_PRODUCTS_URL}

# Compile and run the generator to produce the output/ folder
RUN mvn clean compile exec:java

# Stage 2: Serve the static files with Nginx
FROM nginx:alpine
COPY --from=builder /app/output /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
