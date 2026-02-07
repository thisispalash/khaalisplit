"""
WSGI config for khaaliSplit.

Named export for Gunicorn: config.wsgi:khaaliSplit
"""
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

khaaliSplit = get_wsgi_application()
