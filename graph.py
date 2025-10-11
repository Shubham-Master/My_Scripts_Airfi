import re
import gzip  # Import the gzip library for handling .gz files
import matplotlib.pyplot as plt
import pandas as pd

# File paths for your log files
log_files = ["/Users/sk2/Downloads/logfile-maintenance-20250614_041907-20250615_042123.gz"]

# Regular expression to extract data (updated for current)
pattern = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+).*?current=(\d+\.\d+)A.*?voltage=(\d+\.\d+)")

# Lists to store data
timestamps = []
currents = []
voltages = []

# Function to parse log files
def parse_log_file(file_path):
    with gzip.open(file_path, "rt") as file:  # Use gzip.open with "rt" mode to read text from the .gz file
        for line in file:
            match = pattern.search(line)
            if match:
                timestamps.append(pd.to_datetime(match.group(1)))
                currents.append(float(match.group(2)))
                voltages.append(float(match.group(3)))

# Parse all log files
for log_file in log_files:
    parse_log_file(log_file)

# Create a DataFrame
df = pd.DataFrame({
    'Timestamp': timestamps,
    'Current (A)': currents,
    'Voltage (V)': voltages
})

# Set timestamp as index for plotting
df.set_index('Timestamp', inplace=True)

# Plot the combined graph with dual y-axes
fig, ax1 = plt.subplots(figsize=(14, 7))

# Plot Current (A) on the left y-axis
ax1.plot(df.index, df['Current (A)'], color="green", label="Current (A)")
ax1.set_xlabel("Time")
ax1.set_ylabel("Current (A)", color="green")
ax1.tick_params(axis='y', labelcolor="green")

# Create a second y-axis for Voltage
ax2 = ax1.twinx()
ax2.plot(df.index, df['Voltage (V)'], color="orange", label="Voltage (V)")
ax2.set_ylabel("Voltage (V)", color="orange")
ax2.tick_params(axis='y', labelcolor="orange")

# Add titles and legend
plt.title("Current (A) and Voltage (V) over Time")
fig.tight_layout()
plt.show()
