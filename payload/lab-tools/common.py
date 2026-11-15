"""Helpers run only on the private management EC2 using its IAM role."""
import json
from pathlib import Path
import boto3
import psycopg2
import pymysql

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / 'credify-starter-kit'
CONFIG = json.loads((ROOT / 'lab-config.json').read_text())
CA = '/opt/credify/rds-ca.pem'
SESSION = boto3.Session(region_name=CONFIG['region'])

def secret(key):
    value = SESSION.client('secretsmanager').get_secret_value(SecretId=CONFIG['secrets'][key])
    return json.loads(value['SecretString'])

def pg(which='core', application=False, database=None, host=None):
    key = ('api-db' if which == 'core' else 'erp-db') if application else ('core-admin' if which == 'core' else 'erp-admin')
    auth = secret(key)
    return psycopg2.connect(host=host or CONFIG['endpoints'][which], port=5432,
        dbname=database or ('credify_core' if which == 'core' else 'postgres'),
        user=auth['username'], password=auth['password'], sslmode='verify-full',
        sslrootcert=CA, connect_timeout=15, application_name='credify-5-lab')

def maria():
    auth = secret('maria-admin')
    return pymysql.connect(host=CONFIG['endpoints']['maria'], user=auth['username'],
        password=auth['password'], port=3306, connect_timeout=15,
        ssl_ca=CA, ssl_verify_cert=True, ssl_verify_identity=True,
        autocommit=False)
