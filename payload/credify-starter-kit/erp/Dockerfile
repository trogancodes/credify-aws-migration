FROM odoo:17.0
COPY lab-start.py /opt/credify/lab-start.py
COPY rds-ca.pem /opt/credify/rds-ca.pem
ENV PGSSLMODE=verify-full
ENV PGSSLROOTCERT=/opt/credify/rds-ca.pem
ENTRYPOINT ["python3", "/opt/credify/lab-start.py"]
