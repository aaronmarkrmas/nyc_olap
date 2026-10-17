# Step 4 NYC Taxi OLAP Dashboard 



## Dashboard features

1. Revenue trends: roll up or drill down pickup-date results by day, month, quarter, or year.
2. Location analysis: roll up or drill down pickup or drop-off results by borough and zone.
3. Time demand: group trips by day period or hour of day.
4. Payment and tips: compare trips, revenue, tips, and average trip totals by payment type.
5. Pivot analysis: cross-tabulate a selected row dimension against payment categories.
6. Global slice-and-dice filters: pickup date range, pickup borough, and payment category.
7. CSV export for each report.

## Requirements

- Python 3.10 or later
- MySQL running locally or reachable from your computer
- `nyc_taxi_dw` created by Step 2 and populated by Step 3

## Setup on Windows

Open Command Prompt in this folder and run:

```bat
py -m venv .venv
.venv\Scripts\activate
py -m pip install -r requirements.txt
copy .env.example .env
```

Edit `.env` and set `DB_PASSWORD` to your MySQL password. 

Start the dashboard:

```bat
streamlit run app.py
```

Starts at:  `http://localhost:8501`.

## Before running

1. Confirm both `nyc_taxi_source` and `nyc_taxi_dw` exist in MySQL.
2. Run Steps 1 to 3 successfully and check `etl_report.md` for validation mismatches.
3. Verify the warehouse table and column names match the supplied Step 2 schema.
4. In step 5 Run `mysqlworkbench_validation.sql` in mySQL workbench and follow `TEST_CASES.md` to compare
   MySQL result sets with the dashboard.

If you encountered Lost connection errors: 

```bat
In Workbench

Open Edit → Preferences.
Select SQL Editor.
Find DBMS connection read timeout interval.
Increase it from 30 to 300 or 1000.
Reconnect to MySQL Workbench. 
```
