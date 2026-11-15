import configparser
import os
cfg = configparser.ConfigParser(interpolation=None)
cfg['options'] = {
    'admin_passwd': os.environ['ODOO_MASTER_PASSWORD'],
    'data_dir': '/var/lib/odoo',
    'db_sslmode': 'verify-full',
    'dbfilter': '^credify_erp$',
    'list_db': os.environ.get('ODOO_LIST_DB', 'True'),
    'proxy_mode': 'True',
}
path = '/tmp/credify-odoo.conf'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as out:
    cfg.write(out)
os.execv('/entrypoint.sh', ['/entrypoint.sh', 'odoo', '--config=' + path])
