#!/usr/bin/env python3
"""Create a private, persistent signing identity solely for this local helper.
No system root trust, default keychain/search-list, or macOS privacy settings are changed.
"""
from pathlib import Path
import secrets
import subprocess
import tempfile

root = Path.home() / 'Library/Application Support/CodexPromptOptimizer/Signing'
root.mkdir(parents=True, exist_ok=True)
root.chmod(0o700)
keychain = root / 'local-signing.keychain-db'
password_file = root / 'keychain-password'
certificate = root / 'certificate.pem'
if all(p.exists() for p in [keychain, password_file, certificate]):
    print('已有固定本地签名，保留现有身份。')
    raise SystemExit(0)
if any(p.exists() for p in [keychain, password_file, certificate]):
    raise SystemExit('签名目录不完整；请先检查现有文件，脚本不会覆盖身份。')
password = secrets.token_urlsafe(32)
password_file.touch(mode=0o600)
password_file.write_text(password)
def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('准备签名失败：' + result.stderr.replace(password, '[redacted]'))
with tempfile.TemporaryDirectory(prefix='optimizer-identity-', dir=root) as scratch:
    tmp = Path(scratch)
    config = tmp / 'certificate.cnf'
    config.write_text('''[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Codex Prompt Optimizer Local Signing
O=Sangengxue Local Development
[ext]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
    key = tmp / 'private.pem'
    identity = tmp / 'identity.p12'
    run(['/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '3650', '-config', str(config), '-keyout', str(key), '-out', str(certificate)])
    run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(certificate), '-out', str(identity), '-passout', 'pass:' + password])
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['security', 'import', str(identity), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
    run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)])
print('固定本地签名已建立，未改变系统信任或辅助功能授权。')
