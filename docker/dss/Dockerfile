# EU Digital Signature Service (DSS): checks whether a signature is a
# qualified electronic signature against the EU trusted lists.
# Built from the official sources at a fixed release (esig/dss-demonstrations,
# LGPL-2.1); only its REST validation service is used by BASA.
FROM maven:3.9.16-eclipse-temurin-26 AS build
ARG DSS_VERSION=6.5.1
RUN git clone --depth 1 --branch ${DSS_VERSION} https://github.com/esig/dss-demonstrations.git /src
WORKDIR /src
# as the official Dockerfile: the webapp bundles the standalone app package
RUN mvn -q package -pl dss-standalone-app,dss-standalone-app-package,dss-demo-webapp -P quick,linux

FROM tomcat:11.0.27-jdk25-temurin
# Unpacked, so extra trust (development only) can be added to its classpath
COPY --from=build /src/dss-demo-webapp/target/dss-demo-webapp-*.war /tmp/dss.war
RUN mkdir /usr/local/tomcat/webapps/ROOT \
 && cd /usr/local/tomcat/webapps/ROOT && jar -xf /tmp/dss.war && rm /tmp/dss.war
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
