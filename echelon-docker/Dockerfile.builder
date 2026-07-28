# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml ./
COPY echelon-governance/pom.xml echelon-governance/
COPY echelon-orchestrator/pom.xml echelon-orchestrator/
COPY echelon-workers/pom.xml echelon-workers/
COPY echelon-docker/pom.xml echelon-docker/
COPY echelon-managers/pom.xml echelon-managers/
RUN mvn dependency:go-offline -q

COPY . .
RUN mvn clean package -DskipTests -q

# Stage 2: Runtime
FROM eclipse-temurin:21-jre
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq maven gh \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY --from=build /build/echelon-orchestrator/target/*.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar", "--spring.profiles.active=builder"]
