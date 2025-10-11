import PyPDF2
from datetime import datetime

# Replace with your actual file path
pdf_path = "/Users/sk2/Downloads/Statement1754138292235.PDF"
known_prefix = "riya"

def try_passwords(pdf_path, known_prefix):
    with open(pdf_path, "rb") as f:
        reader = PyPDF2.PdfReader(f)
        for month in range(1, 13):
            for day in range(1, 32):
                try:
                    suffix = f"{month:02}{day:02}"  # e.g., 0101 to 1231
                    password = known_prefix + suffix
                    if reader.decrypt(password):
                        print(f"✅ Password found: {password}")
                        return password
                except Exception as e:
                    pass  # Ignore and continue trying
        print("❌ Password not found in MMDD combinations.")
        return None

if __name__ == "__main__":
    try_passwords(pdf_path, known_prefix)
