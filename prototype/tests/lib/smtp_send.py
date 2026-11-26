#!/usr/bin/env python3
"""Send a raw SMTP message (like swaks) to the prototype mta for scenario tests.

Usage:
  smtp_send.py --from SENDER --to RECIPIENT [--subject S] [--body B] [--server HOST:PORT]

Used by prototype/tests scenarios (ticket E1-11). Replaces the swaks CLI for
environments where swaks is not installed.
"""
import argparse
import smtplib
import ssl
from email.utils import formatdate


def main() -> int:
    p = argparse.ArgumentParser(description="SMTP test sender for prototype scenarios")
    p.add_argument("--server", default="127.0.0.1:2525", help="SMTP host:port (default mta published port)")
    p.add_argument("--from", dest="sender", required=True, help="Envelope sender")
    p.add_argument("--to", required=True, help="Recipient (single address)")
    p.add_argument("--subject", default="scenario test")
    p.add_argument("--body", default="hello scenario")
    p.add_argument("--message-id", default=None, help="Optional explicit Message-ID")
    p.add_argument("--auth-user", default=None, help="SMTP AUTH login (e.g. user@domain)")
    p.add_argument("--auth-pass", default=None, help="SMTP AUTH password")
    p.add_argument("--auth-type", default="plain", choices=["plain", "login", "cram-md5"])
    args = p.parse_args()

    host, port_str = args.server.rsplit(":", 1)
    port = int(port_str)

    msg = (
        f"From: {args.sender}\r\n"
        f"To: {args.to}\r\n"
        f"Subject: {args.subject}\r\n"
        f"Date: {formatdate(usegmt=True)}\r\n"
        f"Message-ID: <{args.message_id or 'scenario-' + formatdate(usegmt=True).replace(' ', '-')}@{args.sender.split('@')[1]}>\r\n"
        f"MIME-Version: 1.0\r\n"
        f"Content-Type: text/plain; charset=UTF-8\r\n"
        "\r\n"
        f"{args.body}\r\n"
    )

    with smtplib.SMTP(host, port, timeout=30) as s:
        s.ehlo("sender.test")
        if args.auth_user is not None:
            s.login(args.auth_user, args.auth_pass)
        s.sendmail(args.sender, [args.to], msg)
        s.quit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
