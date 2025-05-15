# syntax=docker/dockerfile:1.5
FROM maven:3.9.7-eclipse-temurin-21 AS builder
WORKDIR /src
COPY . .
RUN git submodule update --init --recursive
RUN apt-get update && apt-get install -y curl gnupg
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y nodejs \
 && node -v && npm -v
RUN mvn -B clean install
# ─────────────────────────────────────────────────────
#  Runtime — add curl + download-if-missing logic
# ─────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre
WORKDIR /opt/openrailrouting
COPY --from=builder /src/target/railway_routing-*.jar ./openrailrouting.jar
COPY config.yml .

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

#--------------------------------------------------------------------
#  Runtime defaults – override in docker-compose or `docker run -e …`
#--------------------------------------------------------------------
ENV JAVA_OPTS="-Xmx2500m -Xms50m"
ENV OSM_FILE=/data/map.osm.pbf
ENV PBF_URL=https://download.geofabrik.de/europe/monaco-latest.osm.pbf
ENV ORR_ACTION=serve
ENV ORR_PORT=8080

#--------------------------------------------------------------------
#  Clean, newline-safe entry-point
#--------------------------------------------------------------------
RUN cat <<'ENTRYPOINT' >/usr/local/bin/orr-entrypoint && chmod +x /usr/local/bin/orr-entrypoint
#!/bin/sh
set -e

#────────────────────────────────────────────────────────────────────
# Fetch the PBF extract only if it is missing
#────────────────────────────────────────────────────────────────────
if [ ! -f "$OSM_FILE" ]; then
  echo "[ORR] downloading $PBF_URL -> $OSM_FILE"
  mkdir -p "$(dirname "$OSM_FILE")"
  curl -L "$PBF_URL" -o "$OSM_FILE"
fi

#────────────────────────────────────────────────────────────────────
# Launch OpenRailRouting
#────────────────────────────────────────────────────────────────────
exec java $JAVA_OPTS \
  -Ddw.graphhopper.datareader.file="$OSM_FILE" \
  -Ddw.server.application_connectors[0].port=$ORR_PORT \
  -jar /opt/openrailrouting/openrailrouting.jar "$ORR_ACTION" /opt/openrailrouting/config.yml
ENTRYPOINT

RUN apt-get update && apt-get install -y dos2unix && dos2unix /usr/local/bin/orr-entrypoint

ENTRYPOINT ["/usr/local/bin/orr-entrypoint"]
