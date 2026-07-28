# Stage 1: Build
FROM eclipse-temurin:21-jdk AS build
WORKDIR /build
COPY pom.xml ./
COPY echelon-parent/pom.xml echelon-parent/
COPY echelon-governance/pom.xml echelon-governance/
COPY echelon-orchestrator/pom.xml echelon-orchestrator/
COPY echelon-workers/pom.xml echelon-workers/
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
