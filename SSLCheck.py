
import ssl
import socket
from datetime import datetime

hostname = 'airfi.aero'
port = 443

context = ssl.create_default_context()

with socket.create_connection((hostname, port)) as sock:
    with context.wrap_socket(sock, server_hostname=hostname) as ssock:
        cert = ssock.getpeercert()
        print("Certificate for:", hostname)
        print("Valid from:", datetime.strptime(cert['notBefore'], '%b %d %H:%M:%S %Y %Z'))
        print("Valid until:", datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z'))

