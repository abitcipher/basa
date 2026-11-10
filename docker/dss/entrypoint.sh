#!/bin/sh
# Certificates in /trust (DER or PEM, development only) are trusted as
# anchors next to the EU trusted lists. They never make a signature qualified:
# qualification comes only from the trusted lists.
set -e
classes=/usr/local/tomcat/webapps/ROOT/WEB-INF/classes
certs=$(find /trust -maxdepth 1 -type f \( -name '*.der' -o -name '*.pem' \) 2>/dev/null)
if [ -n "$certs" ]; then
  rm -f "$classes/basa-trust.p12"
  for c in $certs; do
    keytool -importcert -noprompt -storetype PKCS12 -keystore "$classes/basa-trust.p12" \
      -storepass basa-trust -alias "$(basename "$c")" -file "$c"
  done
  cat > "$classes/dss-custom.properties" <<PROPS
trusted.source.keystore.type = PKCS12
trusted.source.keystore.filename = basa-trust.p12
trusted.source.keystore.password = basa-trust
PROPS
fi
exec catalina.sh run
