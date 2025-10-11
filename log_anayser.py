import csv
import sys
from collections import defaultdict

def generate_issue_report(input_filepath, output_filepath=None):
    """
    Reads a battery log file and generates a summarized CSV report of detected issues.

    The report includes one line per box per issue type, summarizing all occurrences.

    Args:
        input_filepath (str): The path to the input CSV log file.
        output_filepath (str, optional): The path to save the output CSV report.
                                         If None, the report is printed to the console.
    """
    box_analysis = defaultdict(lambda: defaultdict(list))

    try:
        with open(input_filepath, mode='r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                try:
                    # Extract and convert data, cleaning up whitespace
                    box_id = row['box'].strip()
                    mode = row['mode'].strip()
                    soc = int(row['soc'])
                    current = float(row['current'])
                    voltage = float(row['voltage'])
                    timestamp = row['timestamp'].strip()

                    # Condition 1: Check for 'Early Tapering'
                    if mode == 'maintenance' and soc < 80 and current < 1.0:
                        event_details = {
                            "soc": soc,
                            "current": current,
                            "timestamp": timestamp
                        }
                        box_analysis[box_id]['Early Tapering'].append(event_details)

                    # Condition 2: Check for 'Degraded Pack'
                    if soc > 90 and voltage < 3.00:
                        event_details = {
                            "soc": soc,
                            "voltage": voltage,
                            "timestamp": timestamp
                        }
                        box_analysis[box_id]['Degraded Pack'].append(event_details)

                except (ValueError, KeyError) as e:
                    print(f"Skipping malformed row: {row}. Reason: {e}", file=sys.stderr)
    
    except FileNotFoundError:
        print(f"ERROR: The input file '{input_filepath}' was not found.", file=sys.stderr)
        return
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return

    report_rows = []
    for box_id, issues in sorted(box_analysis.items()):
        for issue_type, events in issues.items():
            if not events:
                continue
            
            event_count = len(events)
            first_event = events[0] 
            
            if issue_type == 'Early Tapering':
                reason = (f"Found {event_count} event(s). First occurred at {first_event['timestamp']} "
                          f"with SoC {first_event['soc']}% and current {first_event['current']:.3f}A.")
            elif issue_type == 'Degraded Pack':
                 reason = (f"Found {event_count} event(s). First occurred at {first_event['timestamp']} "
                          f"with SoC {first_event['soc']}% and voltage {first_event['voltage']:.3f}V.")
            
            report_rows.append([box_id, issue_type, reason])

    header = ['box', 'issue', 'Reason']
    
    if output_filepath:
        try:
            with open(output_filepath, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(header)
                writer.writerows(report_rows)
            print(f"Report generated successfully and saved to '{output_filepath}'")
        except IOError as e:
            print(f"ERROR: Could not write to file '{output_filepath}'. Reason: {e}", file=sys.stderr)
    else:
        writer = csv.writer(sys.stdout)
        writer.writerow(header)
        if report_rows:
            writer.writerows(report_rows)
        else:
            print("--- No issues found in the log file. ---", file=sys.stderr)


if __name__ == "__main__":
    csv_file = '/Users/sk2/Downloads/BATTERY_TRENDS_G9_DATA_V4.csv'
    
    print("--- Generating Console Report ---")
    generate_issue_report(csv_file)
    
    print("\n" + "="*50 + "\n")

    output_file = '/Users/sk2/Downloads/battery_issue_report.csv'
    print(f"--- Saving Report to '{output_file}' ---")
    generate_issue_report(csv_file, output_file)
