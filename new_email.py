import imaplib
import email
from email.header import decode_header
import re
from collections import Counter
from datetime import datetime, timedelta
import traceback

def get_emails():
    try:
        # Calculate the date 7 days ago
        date_7_days_ago = (datetime.now() - timedelta(days=7)).strftime("%d-%b-%Y")
        print(f"Searching emails since: {date_7_days_ago}")

        # Connect to the server
        imap = imaplib.IMAP4_SSL("imap.gmail.com")

        # Login
        username = "shubham.kr@airfi.aero"
        password = "npys dtoo byny uwbn"
        try:
            imap.login(username, password)
        except imaplib.IMAP4.error as e:
            print(f"Login failed: {e}")
            return []

        # Select inbox
        imap.select("inbox")
        status, messages = imap.search(None, f'(FROM "g9-support@airfi.aero" SINCE "{date_7_days_ago}")')
        print(f"IMAP search status: {status}, message list: {messages}")

        if status != 'OK' or not messages[0]:
            print("No matching emails found.")
            imap.logout()
            return []

        email_ids = messages[0].split()
        print(f"Found {len(email_ids)} email(s)")

        serial_numbers = []

        for email_id in email_ids:
            status, msg_data = imap.fetch(email_id, "(RFC822)")
            if status != 'OK':
                print(f"Failed to fetch email ID: {email_id}")
                continue

            for response_part in msg_data:
                if isinstance(response_part, tuple):
                    msg = email.message_from_bytes(response_part[1])

                    # Optional: show subject
                    subject, encoding = decode_header(msg["Subject"])[0]
                    if isinstance(subject, bytes):
                        subject = subject.decode(encoding or 'utf-8', errors='ignore')
                    print(f"\n--- Subject: {subject} ---")

                    if msg.is_multipart():
                        for part in msg.walk():
                            content_type = part.get_content_type()
                            content_disposition = str(part.get("Content-Disposition"))
                            if content_type in ["text/plain", "text/html"] and "attachment" not in content_disposition:
                                try:
                                    body = part.get_payload(decode=True).decode(errors='ignore')
                                    print("=== Body Preview ===")
                                    print(body[:500])
                                    serials = re.findall(r'Serial Number\s*\d\s*:\s*([\d\.]+)', body)
                                    serial_numbers.extend(serials)
                                except Exception as e:
                                    print(f"Error decoding part: {e}")
                    else:
                        try:
                            body = msg.get_payload(decode=True).decode(errors='ignore')
                            print("=== Body Preview ===")
                            print(body[:500])
                            serials = re.findall(r'Serial Number\s*\d\s*:\s*([\d\.]+)', body)
                            serial_numbers.extend(serials)
                        except Exception as e:
                            print(f"Error decoding single-part email: {e}")

        imap.close()
        imap.logout()

        if not serial_numbers:
            print("No serial numbers found in the fetched emails.")

        return serial_numbers

    except Exception as e:
        print("Unexpected error occurred:")
        traceback.print_exc()
        return []

def count_serial_numbers(serial_numbers):
    return Counter(serial_numbers)

if __name__ == "__main__":
    serial_numbers = get_emails()
    counts = count_serial_numbers(serial_numbers)

    print("\nSerial Numbers Reported and Their Counts:")
    if counts:
        for serial, count in counts.items():
            print(f"{serial}: {count} times")
    else:
        print("No serial numbers found.")
