oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ cd backend
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$ poetry run pytest
===================== test session starts ======================
platform linux -- Python 3.12.3, pytest-8.3.0, pluggy-1.6.0
rootdir: /home/oden/Wisdom/backend
configfile: pyproject.toml
plugins: anyio-4.11.0
collected 8 items

tests/test_admin_permissions.py .s                       [ 25%]
tests/test_community_flows.py .s                         [ 50%]
tests/test_courses_public.py .s                          [ 75%]
tests/test_courses_studio.py .s                          [100%]

======================= warnings summary =======================
.venv/lib/python3.12/site-packages/starlette/formparsers.py:12
  /home/oden/Wisdom/backend/.venv/lib/python3.12/site-packages/starlette/formparsers.py:12: PendingDeprecationWarning: Please use `import python_multipart` instead.
    import multipart

.venv/lib/python3.12/site-packages/passlib/utils/__init__.py:854
  /home/oden/Wisdom/backend/.venv/lib/python3.12/site-packages/passlib/utils/__init__.py:854: DeprecationWarning: 'crypt' is deprecated and slated for removal in Python 3.13
    from crypt import crypt as _crypt

tests/test_admin_permissions.py: 6 warnings
tests/test_community_flows.py: 8 warnings
tests/test_courses_public.py: 11 warnings
tests/test_courses_studio.py: 30 warnings
  /home/oden/Wisdom/backend/.venv/lib/python3.12/site-packages/jose/jwt.py:311: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
    now = timegm(datetime.utcnow().utctimetuple())

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
========== 4 passed, 4 skipped, 57 warnings in 3.05s ===========
oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$