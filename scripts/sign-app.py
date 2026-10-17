#!/usr/bin/env python3
"""Sign with an explicit identity or this helper's persistent, private local identity."""
from pathlib import Path
import os
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ.get('OPTIMIZER_SIGN_IDENTITY')
args = ['codesign', '--force']
if identity:
    args += ['--options', 'runtime', '--timestamp']
    if identity == '-':
        raise SystemExit('拒绝临时签名：会导致更新后权限身份改变。请使用固定签名身份。')
else:
    args += ['--timestamp=none']
    signing = Path.home() / 'Library/Application Support/CodexPromptOptimizer/Signing'
    keychain = signing / 'local-signing.keychain-db'
    password_file = signing / 'keychain-password'
    certificate = signing / 'certificate.pem'
    if not all(p.exists() for p in [keychain, password_file, certificate]):
        raise SystemExit('未配置固定签名。请设置 OPTIMIZER_SIGN_IDENTITY，或先运行 setup-local-signing.py。')
    password = password_file.read_text()
    result = subprocess.run(['security', 'unlock-keychain', '-p', password, str(keychain)], capture_output=True)
    if result.returncode:
        raise SystemExit('无法解锁助手专用签名钥匙串，未降级为临时签名。')
    result = subprocess.run(['/usr/bin/openssl', 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1'], capture_output=True, text=True, check=True)
    identity = result.stdout.strip().split('=', 1)[1].replace(':', '')
    args += ['--keychain', str(keychain)]
subprocess.run(args + ['--sign', identity, '--identifier', 'cn.sangengxue.codex-prompt-optimizer', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
