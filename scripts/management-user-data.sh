#!/bin/bash
set -euo pipefail
# No database passwords or AWS credentials are stored in user data.
dnf install -y python3 python3-pip postgresql15 mariadb105 unzip jq nodejs22 cronie
systemctl enable --now amazon-ssm-agent
systemctl enable --now crond
python3 -m venv /opt/credify-venv
/opt/credify-venv/bin/pip install boto3==1.40.55 psycopg2-binary==2.9.10 PyMySQL==1.1.1 sqlparse==0.5.3
if ! command -v node >/dev/null && command -v node-22 >/dev/null; then
  ln -s "$(command -v node-22)" /usr/local/bin/node
fi
install -d -m 755 /opt/credify
curl --fail --silent --show-error --retry 3 \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
  -o /opt/credify/rds-ca.pem
chmod 644 /opt/credify/rds-ca.pem
touch /opt/credify/bootstrap-complete
