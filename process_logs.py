import re
import os

# Function to parse and summarize the log file data
def parse_log_file(file_path):
    with open(file_path, 'r') as file:
        log_data = file.read()

    print("Debug: Log data read successfully.")
    
    # Extract relevant information using regular expressions
    box_ip_pattern = re.compile(r'Box IP:\s*(\S+)')
    date_pattern = re.compile(r'Date:\s*(\d{4}-\d{2}-\d{2})')
    charge_loading_pattern = re.compile(r'Charge @ Loading:\s*(\d+)%')
    charge_end_pattern = re.compile(r'Charge @ End:\s*(\d+)%')
    total_time_pattern = re.compile(r'Total Time Run:\s*(\d+\s*hrs\s*\d+\s*mins)')
    shutdown_reason_pattern = re.compile(r'Shutdown Reason:\s*(\S+)')

    summary = []

    box_ips = box_ip_pattern.findall(log_data)
    dates = date_pattern.findall(log_data)
    charges_loading = charge_loading_pattern.findall(log_data)
    charges_end = charge_end_pattern.findall(log_data)
    total_times = total_time_pattern.findall(log_data)
    shutdown_reasons = shutdown_reason_pattern.findall(log_data)

    # Debug prints to check the extracted data
    print(f"Debug: Found {len(box_ips)} box IPs")
    print(f"Debug: Found {len(dates)} dates")
    print(f"Debug: Found {len(charges_loading)} charges at loading")
    print(f"Debug: Found {len(charges_end)} charges at end")
    print(f"Debug: Found {len(total_times)} total times run")
    print(f"Debug: Found {len(shutdown_reasons)} shutdown reasons")

    for i in range(len(dates)):
        summary.append(f"Summary of Log Data for Box IP: {box_ips[i]}")
        summary.append(f"Date: {dates[i]}")
        summary.append(f"Charge @ Loading: {charges_loading[i]}%")
        summary.append(f"Charge @ End: {charges_end[i]}%")
        summary.append(f"Total Time Run: {total_times[i]}")
        summary.append(f"Shutdown Reason: {shutdown_reasons[i]}")
        summary.append("")

    return summary

# Define the file paths
input_file_path = '/Users/sk2/Downloads/evan_result.txt'
output_file_path = '/Users/sk2/Downloads/Summary.txt'

# Check if the input file exists
if not os.path.exists(input_file_path):
    print(f"Error: The file '{input_file_path}' does not exist.")
else:
    # Generate the summary and write to the output file
    summary = parse_log_file(input_file_path)
    with open(output_file_path, 'w') as output_file:
        for line in summary:
            output_file.write(line + '\n')

    print(f"Summary written to {output_file_path}")
