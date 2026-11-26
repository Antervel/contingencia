#!/usr/bin/env python3
"""IMAP helper for prototype scenario tests (ticket E1-11).

Usage:
  imap_check.py --user USER --password PASS --action count
  imap_check.py --user USER --password PASS --action read [--mailbox INBOX]
  imap_check.py --user USER --password PASS --action wait --expected N [--timeout S]

Prints the result on stdout for bash consumption.
"""
import argparse
import imaplib
import re
import sys
import time


def imap_login(user: str, password: str):
    m = imaplib.IMAP4("127.0.0.1", 1143, timeout=15)
    typ, data = m.login(user, password)
    if typ != "OK":
        raise RuntimeError(f"IMAP login failed for {user}: {data}")
    return m


def mailbox_count(m, mailbox: str) -> int:
    m.select(mailbox)
    typ, data = m.search(None, "ALL")
    if typ != "OK":
        raise RuntimeError(f"IMAP search failed: {data}")
    return len(data[0].split())


def read_message(m, mailbox: str) -> bytes:
    m.select(mailbox)
    typ, data = m.search(None, "ALL")
    if typ != "OK":
        raise RuntimeError(f"IMAP search failed: {data}")
    ids = data[0].split()
    if not ids:
        return b""
    typ, msg_data = m.fetch(ids[-1], "(RFC822)")
    raw = b""
    for response in msg_data:
        if response[0] == "OK":
            for num, payload in response[1]:
                raw = payload if isinstance(payload, bytes) else payload.encode()
    return raw


def main() -> int:
    p = argparse.ArgumentParser(description="IMAP helper for prototype scenarios")
    p.add_argument("--user", required=True)
    p.add_argument("--password", required=True)
    p.add_argument("--action", required=True, choices=["count", "read", "wait"])
    p.add_argument("--mailbox", default="INBOX")
    p.add_argument("--expected", type=int, default=1)
    p.add_argument("--timeout", type=int, default=30)
    args = p.parse_args()

    m = imap_login(args.user, args.password)
    if args.action == "count":
        n = mailbox_count(m, args.mailbox)
        print(n)
        m.logout()
        return 0
    if args.action == "read":
        raw = read_message(m, args.mailbox)
        subject = re.search(rb"(Subject: [^\r\n]*)", raw)
        body = raw.split(b"\r\n\r\n", 1)[-1] if b"\r\n\r\n" in raw else b""
        print(f"SUBJECT:{subject.group(1).decode() if subject else ''}")
        print(f"BODY:{body.decode(errors='replace')}")
        m.logout()
        return 0
    # wait
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        n = mailbox_count(m, args.mailbox)
        if n == args.expected:
            m.logout()
            print("ready")
            return 0
        time.sleep(0.5)
    m.logout()
    print("timeout")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
