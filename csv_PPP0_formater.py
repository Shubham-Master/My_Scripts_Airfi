import pandas as pd

# Load CSV file (try different delimiters if necessary)
file_path = "/Users/sk2/Downloads/data-1741692867196.csv"
df = pd.read_csv(file_path, delimiter=",", engine="python")

# Debug: Print the first few rows and columns
print(df.head())
print(df.columns)

# Ensure 'timestamp' exists
if "timestamp" not in df.columns:
    raise ValueError("Error: 'timestamp' column not found! Check CSV formatting.")

# Convert timestamp to datetime format
df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")

# Extract year-month for monthly grouping
df["year_month"] = df["timestamp"].dt.strftime("%Y-%m")

# Convert bytes to GB (1 GB = 1024^3 bytes)
df["download_gb"] = df["download_bytes"] / (1024 ** 3)
df["upload_gb"] = df["upload_bytes"] / (1024 ** 3)

# Aggregate data per serial per month
df_grouped = df.groupby(["serial", "year_month"]).agg({
    "download_gb": "sum",
    "upload_gb": "sum"
}).reset_index()

# Pivot the table to have months as columns
df_pivot = df_grouped.pivot(index="serial", columns="year_month", values=["download_gb", "upload_gb"])

# Flatten multi-index column names
df_pivot.columns = [f"{col[1]} ({'Download' if col[0] == 'download_gb' else 'Upload'})" for col in df_pivot.columns]
df_pivot.reset_index(inplace=True)

# Save the final CSV
output_file = "/Users/sk2/Downloads/ppp0_usage_summary.csv"
df_pivot.to_csv(output_file, index=False)

print(f"Processed CSV saved as: {output_file}")
