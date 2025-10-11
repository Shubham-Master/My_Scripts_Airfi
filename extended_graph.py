import pandas as pd
import plotly.graph_objs as go
from dash import Dash, dcc, html, Input, Output

file_path = "/Users/sk2/Desktop/Shubham/My Scripts/battery_log.csv"
df = pd.read_csv(file_path, parse_dates=['timestamp'])

required_columns = ['timestamp', 'charge', 'current', 'voltage']
missing = [col for col in required_columns if col not in df.columns]
if missing:
    raise ValueError(f"Missing columns: {missing}")
df['date'] = df['timestamp'].dt.date

app = Dash(__name__)
server = app.server
def break_lines_on_gaps(df_segment, time_col, value_col, max_gap_minutes=5):
    df_segment = df_segment.sort_values(time_col).reset_index(drop=True)
    times = df_segment[time_col]
    values = df_segment[value_col]
    time_diffs = times.diff().dt.total_seconds().div(60).fillna(0)

    times_with_gaps = []
    values_with_gaps = []

    for i in range(len(values)):
        if i > 0 and time_diffs[i] > max_gap_minutes:
            times_with_gaps.append(None)
            values_with_gaps.append(None)
        times_with_gaps.append(times[i])
        values_with_gaps.append(values[i])

    return times_with_gaps, values_with_gaps
app.layout = html.Div([
    html.H1("Battery Trends Viewer"),

    html.Div([
        html.Label("Select Date:"),
        dcc.DatePickerSingle(
            id='date-picker',
            min_date_allowed=min(df['date']),
            max_date_allowed=max(df['date']),
            date=min(df['date']),
        ),
    ], style={"marginBottom": "20px"}),

    dcc.Graph(id='trend-graph'),

    html.Div(id='stats-output', style={"marginTop": "20px", "fontWeight": "bold", "fontSize": "16px"})
])
@app.callback(
    Output('trend-graph', 'figure'),
    Output('stats-output', 'children'),
    Input('date-picker', 'date')
)
def update_graph(selected_date):
    if not selected_date:
        return go.Figure(), "Please select a date."

    selected_date = pd.to_datetime(selected_date).date()
    filtered_df = df[df['date'] == selected_date].copy()

    if filtered_df.empty:
        return go.Figure(), "No data available for the selected date."

    times_current, values_current = break_lines_on_gaps(filtered_df, 'timestamp', 'current')
    times_voltage, values_voltage = break_lines_on_gaps(filtered_df, 'timestamp', 'voltage')
    times_charge, values_charge = break_lines_on_gaps(filtered_df, 'timestamp', 'charge')

    max_current = filtered_df['current'].max()
    avg_current = filtered_df['current'].mean()
    max_charge = filtered_df['charge'].max()
    avg_charge = filtered_df['charge'].mean()
    trace_current = go.Scatter(
        x=times_current,
        y=values_current,
        mode='lines+markers',
        name='Current (A)',
        yaxis='y1',
        hovertemplate='Time: %{x}<br>Current: %{y:.3f} A<extra></extra>'
    )
    trace_voltage = go.Scatter(
        x=times_voltage,
        y=values_voltage,
        mode='lines+markers',
        name='Voltage (V)',
        yaxis='y1',
        hovertemplate='Time: %{x}<br>Voltage: %{y:.3f} V<extra></extra>'
    )
    trace_charge = go.Scatter(
        x=times_charge,
        y=values_charge,
        mode='lines+markers',
        name='Charge',
        yaxis='y2',
        hovertemplate='Time: %{x}<br>Charge: %{y:.2f}<extra></extra>'
    )

    layout = go.Layout(
        title=f"Voltage, Current & Charge on {selected_date}",
        xaxis={
            'title': 'Timestamp',
            'rangeslider': {'visible': True},
        },
        yaxis={
            'title': 'Voltage / Current',
            'side': 'left',
            'tickmode': 'linear',
            'tick0': 0,
            'dtick': 1,
        },
        yaxis2={
            'title': 'Charge',
            'overlaying': 'y',
            'side': 'right',
            'tickmode': 'linear',
            'tick0': 0,
            'dtick': 20,
        },
        hovermode='closest'
    )

    stats = (
        f"📈 Max Current: {max_current:.3f} A "
        f"⚙️ Avg Current: {avg_current:.3f} A "
        f"🔋 Max Charge: {max_charge:.2f} "
        f"⏳ Avg Charge: {avg_charge:.2f}"
    )

    return {'data': [trace_current, trace_voltage, trace_charge], 'layout': layout}, stats

if __name__ == "__main__":
    app.run(debug=True)
