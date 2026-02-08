"""
Django settings for khaaliSplit.

Follows the vps-orchestration pattern (unhinged_lander).
"""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(override=True)

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# ---------------- Security ------------------------------------------------- #

# Fail loud if SECRET_KEY is not set
SECRET_KEY = os.environ['SECRET_KEY']

# Fail loud if DEBUG is not explicitly set
_debug = os.environ.get('DEBUG')
if _debug is None:
  raise ValueError('DEBUG must be explicitly set in environment (true/false)')
DEBUG = _debug.lower() == 'true'

ALLOWED_HOSTS = [
  'khaalisplit.localhost',  # remapped for nginx (dev)
  'localhost',
  '127.0.0.1',
  'khaalisplit.xyz',        # production
  'www.khaalisplit.xyz',    # production (www redirect)
]

CSRF_TRUSTED_ORIGINS = [
  'https://khaalisplit.localhost',
  'https://khaalisplit.xyz',
]


# ---------------- Application definition ---------------------------------- #

INSTALLED_APPS = [
  'django.contrib.admin',
  'django.contrib.auth',
  'django.contrib.contenttypes',
  'django.contrib.sessions',
  'django.contrib.messages',
  'django.contrib.staticfiles',
  # third-party
  'django_htmx',
  'django_extensions',
  # project apps
  'api',
  'web',
  'm',
]

MIDDLEWARE = [
  'django.middleware.security.SecurityMiddleware',
  'django.contrib.sessions.middleware.SessionMiddleware',
  'middleware.wide_event_logging.WideEventLoggingMiddleware',
  'django_htmx.middleware.HtmxMiddleware',
  'django.middleware.common.CommonMiddleware',
  'django.middleware.csrf.CsrfViewMiddleware',
  'django.contrib.auth.middleware.AuthenticationMiddleware',
  'django.contrib.messages.middleware.MessageMiddleware',
  'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
  {
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [BASE_DIR / 'templates'],
    'APP_DIRS': True,
    'OPTIONS': {
      'context_processors': [
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
        'config.context_processors.goatcounter_url',
        'config.context_processors.active_tab',
      ],
    },
  },
]

WSGI_APPLICATION = 'config.wsgi.khaaliSplit'


# ---------------- Database ------------------------------------------------ #

DATABASES = {
  'default': {
    'ENGINE': 'django.db.backends.postgresql',
    'NAME': os.getenv('PG_DATABASE', ''),
    'USER': os.getenv('PG_USER', ''),
    'PASSWORD': os.getenv('PG_PASS', ''),
    'HOST': os.getenv('PG_HOST', ''),
    'PORT': os.getenv('PG_PORT', '5432'),
    'CONN_MAX_AGE': 600,
  }
}

# ---------------- Auth ---------------------------------------------------- #

AUTH_USER_MODEL = 'api.User'

AUTH_PASSWORD_VALIDATORS = [
  {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
  {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
  {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
  {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]


# ---------------- Internationalization ------------------------------------ #

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True


# ---------------- Static files -------------------------------------------- #

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [BASE_DIR / 'static']

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# ---------------- Logging ------------------------------------------------- #

LOGGING = {
  'version': 1,
  'disable_existing_loggers': False,
  'formatters': {
    'wide_event': {
      'format': '%(message)s',
    },
  },
  'handlers': {
    'wide_event_console': {
      'class': 'logging.StreamHandler',
      'formatter': 'wide_event',
    },
  },
  'loggers': {
    'wide_event': {
      'handlers': ['wide_event_console'],
      'level': 'INFO',
      'propagate': False,
    },
  },
}


# ---------------- Web3 / Contract Config ---------------------------------- #

SEPOLIA_RPC_URL = os.getenv('SEPOLIA_RPC_URL', '')
BACKEND_PRIVATE_KEY = os.getenv('BACKEND_PRIVATE_KEY', '')
GATEWAY_SIGNER_KEY = os.getenv('GATEWAY_SIGNER_KEY', '')

# Contract addresses (Sepolia)
CONTRACT_FRIENDS = os.getenv('CONTRACT_FRIENDS', '')
CONTRACT_GROUPS = os.getenv('CONTRACT_GROUPS', '')
CONTRACT_EXPENSES = os.getenv('CONTRACT_EXPENSES', '')
CONTRACT_SETTLEMENT = os.getenv('CONTRACT_SETTLEMENT', '')
CONTRACT_RESOLVER = os.getenv('CONTRACT_RESOLVER', '')
