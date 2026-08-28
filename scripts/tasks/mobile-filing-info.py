#!/usr/bin/env python3
"""Extract Android/iOS APP filing identifiers and certificate fingerprints."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa


REPO_ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = REPO_ROOT / "apps" / "android"
ANDROID_GRADLE = ANDROID_ROOT / "app" / "build.gradle.kts"
ANDROID_SIGNING_PROPERTIES = ANDROID_ROOT / "keystore.properties"
IOS_PROJECT = REPO_ROOT / "apps" / "ios" / "NanoOps.xcodeproj" / "project.pbxproj"
DEFAULT_OUTPUT = REPO_ROOT / "artifacts" / "mobile" / "NanoOps-Filing-Info.txt"


def _properties(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _match_one(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text)
    if match is None:
        raise RuntimeError(f"Unable to find {label}")
    return match.group(1)


def _load_android_certificate() -> x509.Certificate:
    properties = _properties(ANDROID_SIGNING_PROPERTIES)
    required = {"storeFile", "storePassword", "keyAlias"}
    missing = sorted(required.difference(properties))
    if missing:
        raise RuntimeError(f"Missing Android signing properties: {', '.join(missing)}")

    keystore = ANDROID_ROOT / properties["storeFile"]
    if not keystore.is_file():
        raise RuntimeError(f"Android release keystore not found: {keystore}")

    keytool = shutil.which("keytool")
    if keytool is None:
        raise RuntimeError("keytool was not found on PATH")

    environment = os.environ.copy()
    environment["NANOOPS_STORE_PASSWORD"] = properties["storePassword"]
    command = [
        keytool,
        "-exportcert",
        "-keystore",
        str(keystore),
        "-alias",
        properties["keyAlias"],
        "-storepass:env",
        "NANOOPS_STORE_PASSWORD",
    ]
    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
    )
    return x509.load_der_x509_certificate(completed.stdout)


def _load_certificate(path: Path) -> x509.Certificate:
    data = path.read_bytes()
    if b"-----BEGIN CERTIFICATE-----" in data:
        return x509.load_pem_x509_certificate(data)
    return x509.load_der_x509_certificate(data)


def _public_key_lines(certificate: x509.Certificate) -> list[str]:
    public_key = certificate.public_key()
    spki_hex = public_key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).hex().upper()
    if isinstance(public_key, rsa.RSAPublicKey):
        modulus = public_key.public_numbers().n
        return [
            f"公钥（模数，10进制，备案推荐）：{modulus}",
            f"公钥（模数，16进制）：{modulus:X}",
            f"公钥（SPKI DER，16进制）：{spki_hex}",
        ]
    if isinstance(public_key, ec.EllipticCurvePublicKey):
        point_hex = public_key.public_bytes(
            serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint,
        ).hex().upper()
        return [
            f"公钥（EC 非压缩点，16进制）：{point_hex}",
            f"公钥（SPKI DER，16进制）：{spki_hex}",
        ]
    return [f"公钥（SPKI DER，16进制）：{spki_hex}"]


def _fingerprint(certificate: x509.Certificate, algorithm: hashes.HashAlgorithm) -> str:
    return certificate.fingerprint(algorithm).hex().upper()


def _android_section() -> list[str]:
    gradle_text = ANDROID_GRADLE.read_text(encoding="utf-8")
    package_name = _match_one(r'applicationId\s*=\s*"([^"]+)"', gradle_text, "Android applicationId")
    version_name = _match_one(r'getOrElse\("([^"]+)"\)', gradle_text, "Android versionName")
    version_code = _match_one(r"versionCode\s*=\s*(\d+)", gradle_text, "Android versionCode")
    certificate = _load_android_certificate()

    return [
        "【Android】",
        f"APP名称：NanoOps",
        f"包名：{package_name}",
        f"版本：{version_name}（versionCode {version_code}）",
        *_public_key_lines(certificate),
        f"签名MD5（32位16进制，无冒号）：{_fingerprint(certificate, hashes.MD5())}",
        f"签名SHA-1（备用）：{_fingerprint(certificate, hashes.SHA1())}",
        f"证书主题：{certificate.subject.rfc4514_string()}",
        f"证书有效期：{certificate.not_valid_before_utc.date()} 至 {certificate.not_valid_after_utc.date()}",
    ]


def _ios_section(certificate_path: Path | None) -> list[str]:
    project_text = IOS_PROJECT.read_text(encoding="utf-8")
    bundle_id = _match_one(
        r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;\s]+);", project_text, "iOS Bundle ID"
    )
    lines = [
        "【iOS】",
        "APP名称：NanoOps",
        f"Bundle ID：{bundle_id}",
    ]
    if certificate_path is None:
        lines.extend(
            [
                "平台公钥：待 Apple Distribution 证书（.cer）生成后提取",
                "签名SHA-1（备案表中的“签名MD5值”）：待 Apple Distribution 证书生成后提取",
            ]
        )
        return lines

    certificate = _load_certificate(certificate_path)
    lines.extend(_public_key_lines(certificate))
    lines.extend(
        [
            f"签名SHA-1（40位16进制，无冒号）：{_fingerprint(certificate, hashes.SHA1())}",
            f"证书主题：{certificate.subject.rfc4514_string()}",
            f"证书有效期：{certificate.not_valid_before_utc.date()} 至 {certificate.not_valid_after_utc.date()}",
        ]
    )
    return lines


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ios-cert",
        type=Path,
        help="Optional Apple Distribution certificate in DER .cer or PEM format",
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    sections = [
        "NanoOps APP备案特征信息",
        "域名：https://nanoops.netok.cn",
        "备案填写时 Android 使用 MD5；iOS 使用 Apple Distribution 证书的 SHA-1。",
        "",
        *_android_section(),
        "",
        *_ios_section(args.ios_cert),
        "",
        "注意：公钥和指纹必须与最终上架/分发包实际使用的证书一致。",
    ]
    report = "\n".join(sections) + "\n"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report, encoding="utf-8")
    print(report, end="")
    print(f"报告文件：{args.out}")


if __name__ == "__main__":
    main()
