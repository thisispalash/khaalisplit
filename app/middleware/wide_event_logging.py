"""
Wide-event logging middleware.

Emits one JSON log per request containing everything you'd want to know:
timestamp, method, path, status, duration, user, IP, user agent, and any
errors or extra context that views chose to attach.

Inspired by https://loggingsucks.com — one wide event per unit of work.
Adapted from unhinged_lander pattern for khaaliSplit.

Usage in views:
    request._wide_event['extra']['some_key'] = 'some_value'
    request._wide_event['errors'].append({'type': 'ValidationError', 'msg': '...'})
"""
import json
import logging
import time
import traceback

logger = logging.getLogger('wide_event')


class WideEventLoggingMiddleware:
  """
  Middleware that emits one structured JSON log per request.

  Place after SessionMiddleware, before CommonMiddleware:
    - Needs session for user info
    - Should run early to capture timing accurately
  """

  def __init__(self, get_response):
    self.get_response = get_response

  def __call__(self, request):
    # Attach wide event context for views to enrich
    request._wide_event = {
      'errors': [],
      'extra': {},
    }

    start_time = time.monotonic()
    response = self.get_response(request)
    duration_ms = (time.monotonic() - start_time) * 1000

    self._emit_log(request, response, duration_ms)
    return response

  def process_exception(self, request, exception):
    """Capture unhandled exceptions into the wide event."""
    if hasattr(request, '_wide_event'):
      request._wide_event['errors'].append({
        'type': type(exception).__name__,
        'msg': str(exception),
        'traceback': traceback.format_exc(),
      })
    # Return None so Django's default exception handling continues
    return None

  def _emit_log(self, request, response, duration_ms):
    """Build and emit the wide event log."""
    # Get client IP from X-Forwarded-For (set by nginx proxy_headers)
    ip = request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
    if not ip:
      ip = request.META.get('REMOTE_ADDR', '')

    # Get user info — khaaliSplit uses subname as username
    user = None
    subname = None
    if hasattr(request, 'user') and request.user.is_authenticated:
      user = str(request.user)
      subname = getattr(request.user, 'subname', None)

    event = {
      'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
      'method': request.method,
      'path': request.path,
      'query_string': request.META.get('QUERY_STRING', ''),
      'status_code': response.status_code,
      'duration_ms': round(duration_ms, 2),
      'ip': ip,
      'user': user,
      'subname': subname,
      'user_agent': request.META.get('HTTP_USER_AGENT', ''),
      'content_type': getattr(request, 'content_type', ''),
      'is_htmx': bool(getattr(request, 'htmx', False)),
      'errors': request._wide_event.get('errors', []),
      'extra': request._wide_event.get('extra', {}),
    }

    # Log level based on status code
    if response.status_code >= 500:
      logger.error(json.dumps(event))
    elif response.status_code >= 400:
      logger.warning(json.dumps(event))
    else:
      logger.info(json.dumps(event))
