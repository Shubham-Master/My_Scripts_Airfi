import imaplib
import email
from email.utils import parsedate_to_datetime
import re
import csv
from datetime import datetime, timedelta

def get_wifi_remarks():
    date_1_day_ago = (datetime.now() - timedelta(days=1)).strftime("%d-%b-%Y")

    imap = imaplib.IMAP4_SSL("imap.gmail.com")
    username = "shubham.kr@airfi.aero"
    password = "npys dtoo byny uwbn"
    imap.login(username, password)
    imap.select("inbox")

    status, messages = imap.search(None, f'(FROM "g9-support@airfi.aero" SINCE "{date_1_day_ago}")')
    email_ids = messages[0].split()

    results = []

    for email_id in email_ids:
        status, msg_data = imap.fetch(email_id, "(RFC822)")
        for response_part in msg_data:
            if isinstance(response_part, tuple):
                msg = email.message_from_bytes(response_part[1])

                # Parse email datetime
                raw_date = msg.get("Date")
                try:
                    email_date = parsedate_to_datetime(raw_date)
                    email_date_str = email_date.strftime("%Y-%m-%d %H:%M:%S")
                except:
                    email_date_str = "Unknown"

                # Get email body content
                body = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        content_type = part.get_content_type()
                        if content_type in ["text/plain", "text/html"] and "attachment" not in str(part.get("Content-Disposition")):
                            try:
                                body = part.get_payload(decode=True).decode()
                                break
                            except:
                                continue
                else:
                    try:
                        body = msg.get_payload(decode=True).decode()
                    except:
                        continue

                # Extract Serial Numbers
                ip_matches = re.findall(r'Serial Number\s*\d\s*:\s*(10\.\d+\.\d+\.\d+)', body)
                ip1 = ip_matches[0] if len(ip_matches) > 0 else "N/A"
                ip2 = ip_matches[1] if len(ip_matches) > 1 else "N/A"

                # Extract Inbound Flight number
                flight_match = re.search(r'In\s*Bound\s*Flight.*?Flight\s*No\s*:\s*([A-Z0-9]+)', body, re.IGNORECASE)
                if not flight_match:
                    # fallback to outbound if inbound not present
                    flight_match = re.search(r'Out\s*Bound\s*Flight.*?Flight\s*No\s*:\s*([A-Z0-9]+)', body, re.IGNORECASE)
                flight = flight_match.group(1).replace(" ", "") if flight_match else "UNKNOWN"

                # Extract Remarks
                remarks_match = re.search(r'Remarks\s*:\s*(.*?)\n', body, re.IGNORECASE)
                remarks = remarks_match.group(1).strip() if remarks_match and remarks_match.group(1).strip() else "N/A"

                results.append({
                    "flight": flight,
                    "datetime": email_date_str,
                    "box_ip1": ip1,
                    "box_ip2": ip2,
                    "remarks": remarks
                })

    imap.close()
    imap.logout()

    return results

def save_to_csv(data, filename="wifi_issues_report.csv"):
    keys = ["flight", "datetime", "box_ip1", "box_ip2", "remarks"]
    with open(filename, "w", newline="") as output_file:
        dict_writer = csv.DictWriter(output_file, fieldnames=keys)
        dict_writer.writeheader()
        dict_writer.writerows(data)

if __name__ == "__main__":
    remark_data = get_wifi_remarks()
    save_to_csv(remark_data)
    print(f"✅ Extracted {len(remark_data)} entries and saved to wifi_issues_report.csv.")
