#!/usr/bin/env python3
import imaplib
import email
from email import policy
from email.utils import parsedate_to_datetime
import os
import re
import csv
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

IMAP_HOST = "imap.gmail.com"
FROM_ADDR = "g9-support@airfi.aero"
# how many days back to search
DAYS_BACK = 15
# output CSV path (in the same directory as this script)
OUTFILE = os.path.join(os.path.dirname(__file__), "g9_serials_report.csv")

# Regex patterns (flexible)
IP_RE = re.compile(r'(?:Serial(?:\s*Number)?\s*\d*\s*[:\-]?\s*|Box\s*IP\s*[:\-]?\s*)(\d{1,3}(?:\.\d{1,3}){3})')
FLIGHT_RE = re.compile(r'Flight\s*[:\-]\s*([A-Za-z0-9\- ]{2,})')
REMARKS_RE = re.compile(r'Remarks?\s*[:\-]\s*(.+)')

def _clean_html(text: str) -> str:
    # very simple HTML tag remover; good enough for extraction
    return re.sub(r'<[^>]+>', ' ', text)

def _get_body_from_msg(msg: email.message.Message) -> str:
    """Return best-effort decoded body text (plain first, then html-stripped)."""
    plain_candidates = []
    html_candidates = []
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_maintype() == 'multipart':
                continue
            ctype = part.get_content_type()
            try:
                payload = part.get_content()
            except Exception:
                # fallback to manual decode if policy.get_content fails
                try:
                    payload = part.get_payload(decode=True)
                    payload = payload.decode(part.get_content_charset() or 'utf-8', errors='replace')
                except Exception:
                    payload = ''
            if ctype == "text/plain":
                plain_candidates.append(str(payload))
            elif ctype == "text/html":
                html_candidates.append(_clean_html(str(payload)))
    else:
        try:
            payload = msg.get_content()
        except Exception:
            try:
                payload = msg.get_payload(decode=True)
                payload = payload.decode(msg.get_content_charset() or 'utf-8', errors='replace')
            except Exception:
                payload = ''
        if msg.get_content_type() == "text/plain":
            plain_candidates.append(str(payload))
        else:
            html_candidates.append(_clean_html(str(payload)))

    if plain_candidates:
        return "\n\n".join(plain_candidates)
    if html_candidates:
        return "\n\n".join(html_candidates)
    return ""

def _extract_fields(text: str):
    """Extract serials (IPs), flight, remarks from body text."""
    serials = IP_RE.findall(text)

    # Only take first reasonably-looking flight/remarks if present
    flight_match = FLIGHT_RE.search(text)
    remarks_match = REMARKS_RE.search(text)

    flight = flight_match.group(1).strip() if flight_match else ""
    # stop remarks at line break if it’s a long paragraph
    remarks = ""
    if remarks_match:
        remarks = remarks_match.group(1).strip()
        remarks = remarks.splitlines()[0].strip()

    return serials, flight, remarks

def _fmt_since(days: int) -> str:
    # IMAP expects DD-Mon-YYYY (e.g., 01-Sep-2025)
    target = (datetime.now() - timedelta(days=days)).strftime("%d-%b-%Y")
    return target

def get_emails():
    username = os.environ.get("GMAIL_USER")  # e.g. shubham.kr@airfi.aero
    password = os.environ.get("GMAIL_APP_PASSWORD")  # your app password

    if not username or not password:
        raise SystemExit("Set env vars GMAIL_USER and GMAIL_APP_PASSWORD before running.")

    imap = imaplib.IMAP4_SSL(IMAP_HOST)
    imap.login(username, password)
    try:
        imap.select("INBOX")
        since = _fmt_since(DAYS_BACK)
        status, data = imap.search(None, f'(FROM "{FROM_ADDR}" SINCE "{since}")')
        if status != "OK":
            raise RuntimeError(f"IMAP search failed: {status} {data}")

        email_ids = data[0].split()
        rows = []  # list of dicts with: datetime_ist, serial, flight, remarks, subject, message_id

        for eid in email_ids:
            status, parts = imap.fetch(eid, "(RFC822)")
            if status != "OK":
                continue
            for part in parts:
                if not isinstance(part, tuple):
                    continue
                msg = email.message_from_bytes(part[1], policy=policy.default)

                # Email datetime → IST
                try:
                    msg_dt = parsedate_to_datetime(msg.get('Date'))
                except Exception:
                    msg_dt = None
                if msg_dt and msg_dt.tzinfo:
                    msg_dt_ist = msg_dt.astimezone(ZoneInfo("Asia/Kolkata"))
                elif msg_dt:
                    # assume UTC if naive (rare)
                    msg_dt_ist = msg_dt.replace(tzinfo=ZoneInfo("UTC")).astimezone(ZoneInfo("Asia/Kolkata"))
                else:
                    msg_dt_ist = None

                body = _get_body_from_msg(msg)
                serials, flight, remarks = _extract_fields(body)

                # If nothing matched, still record a row to help debugging
                if not serials:
                    rows.append({
                        "datetime_ist": msg_dt_ist.isoformat() if msg_dt_ist else "",
                        "serial": "",
                        "flight": flight,
                        "remarks": remarks,
                        "subject": (msg.get('Subject') or "").strip(),
                        "message_id": (msg.get('Message-ID') or "").strip(),
                    })
                else:
                    for s in serials:
                        rows.append({
                            "datetime_ist": msg_dt_ist.isoformat() if msg_dt_ist else "",
                            "serial": s,
                            "flight": flight,
                            "remarks": remarks,
                            "subject": (msg.get('Subject') or "").strip(),
                            "message_id": (msg.get('Message-ID') or "").strip(),
                        })
        return rows
    finally:
        try:
            imap.close()
        except Exception:
            pass
        imap.logout()

def summarize_and_write(rows):
    # Count serial occurrences
    ctr = Counter(r["serial"] for r in rows if r["serial"])
    print("Serial Numbers Reported and Their Counts:")
    for serial, count in ctr.most_common():
        print(f"{serial}: {count} time(s)")

    # Write CSV
    fieldnames = ["datetime_ist", "serial", "flight", "remarks", "subject", "message_id"]
    with open(OUTFILE, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"\nCSV written to: {OUTFILE}")

if __name__ == "__main__":
    rows = get_emails()
    summarize_and_write(rows)
