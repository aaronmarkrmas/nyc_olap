import os
from datetime import date

import pandas as pd
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

st.set_page_config(
    page_title="NYC Taxi OLAP Dashboard",
    page_icon="🚕",
    layout="wide",
)

st.title("NYC Yellow Taxi OLAP Dashboard")
st.caption("STADVDB MCO1 · June 2024 · Data source: nyc_taxi_dw")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "nyc_taxi_dw")


@st.cache_resource
def get_engine():
    url = URL.create(
        drivername="mysql+pymysql",
        username=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        query={"charset": "utf8mb4"},
    )
    return create_engine(url, pool_pre_ping=True)


def read_df(sql, params=None):
    """Run a parameterized SELECT and return its results as a DataFrame."""
    with get_engine().connect() as connection:
        return pd.read_sql(text(sql), connection, params=params or {})


def scalar(sql, params=None):
    df = read_df(sql, params)
    return df.iloc[0, 0] if not df.empty else 0


def money(value):
    return f"${value:,.2f}"


# The supplied ETL defaults to pickup dates from June 1 through June 30, 2024.
default_filters = {
    "start_date": date(2024, 6, 1),
    "end_date": date(2024, 6, 30),
    "borough": "All boroughs",
    "payment_category": "All payment categories",
}
if "applied_filters" not in st.session_state:
    st.session_state.applied_filters = default_filters.copy()

with st.sidebar:
    st.header("Slice and dice")
    with st.form("filters_form"):
        pending_start_date = st.date_input(
            "Pickup date from",
            value=st.session_state.applied_filters["start_date"],
        )
        pending_end_date = st.date_input(
            "Pickup date to",
            value=st.session_state.applied_filters["end_date"],
        )

        try:
            borough_rows = read_df(
                """
                SELECT DISTINCT borough
                FROM dim_location
                WHERE borough IS NOT NULL AND TRIM(borough) <> ''
                ORDER BY borough
                """
            )
            borough_options = ["All boroughs"] + borough_rows["borough"].astype(str).tolist()
        except Exception as exc:
            st.error("Could not connect to MySQL or read dim_location.")
            st.code(str(exc))
            st.info("Check your .env settings, MySQL service, and that Step 2 and Step 3 completed.")
            st.stop()

        pending_borough = st.selectbox(
            "Pickup borough",
            borough_options,
            index=(
                borough_options.index(st.session_state.applied_filters["borough"])
                if st.session_state.applied_filters["borough"] in borough_options
                else 0
            ),
        )

        payment_rows = read_df(
            """
            SELECT DISTINCT payment_category
            FROM dim_payment_type
            WHERE payment_category IS NOT NULL AND TRIM(payment_category) <> ''
            ORDER BY payment_category
            """
        )
        payment_options = ["All payment categories"] + payment_rows["payment_category"].astype(str).tolist()
        pending_payment_category = st.selectbox(
            "Payment category",
            payment_options,
            index=(
                payment_options.index(st.session_state.applied_filters["payment_category"])
                if st.session_state.applied_filters["payment_category"] in payment_options
                else 0
            ),
        )
        apply_filters = st.form_submit_button("Apply filters", type="primary")

    if apply_filters:
        if pending_start_date > pending_end_date:
            st.error("The start date must be on or before the end date.")
        else:
            st.session_state.applied_filters = {
                "start_date": pending_start_date,
                "end_date": pending_end_date,
                "borough": pending_borough,
                "payment_category": pending_payment_category,
            }
            st.success("Filters applied.")

start_date = st.session_state.applied_filters["start_date"]
end_date = st.session_state.applied_filters["end_date"]
borough = st.session_state.applied_filters["borough"]
payment_category = st.session_state.applied_filters["payment_category"]

params = {
    "start_date": start_date,
    "end_date": end_date,
    "borough": borough,
    "payment_category": payment_category,
}

FILTERS = """
    dpu.full_date >= :start_date
    AND dpu.full_date <= :end_date
    AND (:borough = 'All boroughs' OR lpu.borough = :borough)
    AND (:payment_category = 'All payment categories'
         OR p.payment_category = :payment_category)
"""

# Global KPI cards
kpi_sql = f"""
SELECT
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS total_revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance,
    COALESCE(SUM(f.tip_amount), 0) AS total_tips
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE {FILTERS}
"""
kpis = read_df(kpi_sql, params)
if kpis.empty:
    trip_count, total_revenue, avg_distance, total_tips = 0, 0, 0, 0
else:
    row = kpis.iloc[0]
    trip_count = int(row["trip_count"])
    total_revenue = float(row["total_revenue"])
    avg_distance = float(row["avg_distance"])
    total_tips = float(row["total_tips"])

c1, c2, c3, c4 = st.columns(4)
c1.metric("Trips", f"{trip_count:,}")
c2.metric("Total revenue", money(total_revenue))
c3.metric("Average distance", f"{avg_distance:.2f} mi")
c4.metric("Total tips", money(total_tips))

st.caption(
    f"Filters: {start_date:%b %d, %Y} – {end_date:%b %d, %Y} · "
    f"{borough} · {payment_category}"
)

tab_trends, tab_locations, tab_time, tab_payments, tab_pivot = st.tabs(
    [
        "1 · Revenue trends",
        "2 · Location analysis",
        "3 · Time demand",
        "4 · Payment & tips",
        "5 · Pivot analysis",
    ]
)

with tab_trends:
    st.subheader("Revenue and trip trends")
    st.write(
        "Use the date hierarchy to roll up from day to year or drill down from "
        "year to day."
    )
    grain = st.selectbox(
        "Date hierarchy level",
        ["Day", "Month", "Quarter", "Year"],
        index=1,
        key="trend_grain",
        help="Day → Month → Quarter → Year supports drill-down and roll-up.",
    )
    date_groups = {
        "Day": ("DATE_FORMAT(dpu.full_date, '%Y-%m-%d')", "pickup_day"),
        "Month": ("DATE_FORMAT(dpu.full_date, '%Y-%m')", "pickup_month"),
        "Quarter": ("CONCAT(YEAR(dpu.full_date), '-Q', QUARTER(dpu.full_date))", "pickup_quarter"),
        "Year": ("CAST(YEAR(dpu.full_date) AS CHAR)", "pickup_year"),
    }
    group_expr, group_label = date_groups[grain]
    trend_sql = f"""
    SELECT
        {group_expr} AS period,
        COUNT(*) AS trip_count,
        COALESCE(SUM(f.total_amount), 0) AS revenue,
        COALESCE(SUM(f.tip_amount), 0) AS tips,
        COALESCE(AVG(f.total_amount), 0) AS avg_fare_total
    FROM fact_trip f
    JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
    JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
    JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
    WHERE {FILTERS}
    GROUP BY {group_expr}
    ORDER BY MIN(dpu.full_date)
    """
    trend = read_df(trend_sql, params)
    if trend.empty:
        st.info("No trips match the selected filters.")
    else:
        chart_data = trend.set_index("period")[["revenue", "tips"]]
        st.line_chart(chart_data)
        st.dataframe(trend, use_container_width=True, hide_index=True)
        csv = trend.to_csv(index=False).encode("utf-8")
        st.download_button("Download trend results (CSV)", csv, "revenue_trends.csv", "text/csv")

with tab_locations:
    st.subheader("Pickup and drop-off locations")
    location_level = st.selectbox(
        "Location hierarchy level",
        ["Zone", "Borough"],
        help="Zone is the detailed level; Borough is the rolled-up level.",
        key="location_level",
    )
    location_role = st.radio(
        "Analyze location by",
        ["Pickup", "Drop-off"],
        horizontal=True,
        key="location_role",
    )
    if location_role == "Pickup":
        location_key = "f.pickup_location_key"
        location_date_key = "f.pickup_date_key"
        location_alias = "loc"
    else:
        location_key = "f.dropoff_location_key"
        location_date_key = "f.dropoff_date_key"
        location_alias = "loc"

    # Date filtering follows pickup dates consistently with the dashboard's global filter.
    # The selected borough filter remains a pickup-borough slice, as labeled in the sidebar.
    if location_level == "Borough":
        location_group = f"{location_alias}.borough"
        location_select = f"{location_alias}.borough AS borough, NULL AS zone"
        location_group_label = "borough"
    else:
        location_group = f"{location_alias}.borough, {location_alias}.zone_name"
        location_select = (
            f"{location_alias}.borough AS borough, "
            f"{location_alias}.zone_name AS zone"
        )
        location_group_label = "zone"

    location_sql = f"""
    SELECT
        {location_select},
        COUNT(*) AS trip_count,
        COALESCE(SUM(f.total_amount), 0) AS revenue,
        COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance_mi
    FROM fact_trip f
    JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
    JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
    JOIN dim_location {location_alias} ON {location_alias}.location_key = {location_key}
    JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
    WHERE {FILTERS}
    GROUP BY {location_group}
    ORDER BY trip_count DESC
    LIMIT 25
    """
    locations = read_df(location_sql, params)
    if locations.empty:
        st.info("No locations match the selected filters.")
    else:
        chart_column = "zone" if location_level == "Zone" else "borough"
        st.bar_chart(locations.head(15).set_index(chart_column)["trip_count"])
        st.dataframe(locations, use_container_width=True, hide_index=True)
        st.download_button(
            "Download location results (CSV)",
            locations.to_csv(index=False).encode("utf-8"),
            "location_analysis.csv",
            "text/csv",
        )

with tab_time:
    st.subheader("Demand by time of day")
    time_group = st.selectbox(
        "Time grouping",
        ["Day period", "Hour of day"],
        key="time_group",
    )
    if time_group == "Day period":
        time_expr = "tm.day_period"
        order_expr = "MIN(tm.day_period_order)"
        time_label = "day_period"
    else:
        time_expr = "tm.hour_24"
        order_expr = "tm.hour_24"
        time_label = "hour_24"

    time_sql = f"""
    SELECT
        {time_expr} AS time_bucket,
        COUNT(*) AS trip_count,
        COALESCE(SUM(f.total_amount), 0) AS revenue,
        COALESCE(AVG(f.trip_duration_sec) / 60, 0) AS avg_duration_minutes
    FROM fact_trip f
    JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
    JOIN dim_time tm ON tm.time_key = f.pickup_time_key
    JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
    JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
    WHERE {FILTERS}
    GROUP BY {time_expr}
    ORDER BY {order_expr}
    """
    time_data = read_df(time_sql, params)
    if time_data.empty:
        st.info("No trips match the selected filters.")
    else:
        st.bar_chart(time_data.set_index("time_bucket")["trip_count"])
        st.dataframe(time_data, use_container_width=True, hide_index=True)
        st.download_button(
            "Download time results (CSV)",
            time_data.to_csv(index=False).encode("utf-8"),
            "time_demand.csv",
            "text/csv",
        )

with tab_payments:
    st.subheader("Payment and tipping patterns")
    payment_sql = f"""
    SELECT
        p.payment_category,
        p.payment_type_desc,
        p.is_tip_recorded,
        COUNT(*) AS trip_count,
        COALESCE(SUM(f.total_amount), 0) AS revenue,
        COALESCE(SUM(f.tip_amount), 0) AS total_tips,
        COALESCE(AVG(f.tip_amount), 0) AS average_tip_per_trip,
        COALESCE(AVG(f.total_amount), 0) AS average_total_per_trip
    FROM fact_trip f
    JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
    JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
    JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
    WHERE {FILTERS}
    GROUP BY p.payment_category, p.payment_type_desc, p.is_tip_recorded
    ORDER BY revenue DESC
    """
    payment_data = read_df(payment_sql, params)
    if payment_data.empty:
        st.info("No payment records match the selected filters.")
    else:
        st.bar_chart(payment_data.set_index("payment_type_desc")["revenue"])
        st.dataframe(payment_data, use_container_width=True, hide_index=True)
        st.caption(
            "Interpret tip values with the payment method in mind. "
            "The dimension's is_tip_recorded flag indicates whether tips are captured in the source."
        )
        st.download_button(
            "Download payment results (CSV)",
            payment_data.to_csv(index=False).encode("utf-8"),
            "payment_tips.csv",
            "text/csv",
        )

with tab_pivot:
    st.subheader("Pivot analysis")
    st.write(
        "Pivot the filtered measures by placing a selected dimension on rows "
        "and payment categories on columns."
    )
    pivot_row = st.selectbox(
        "Pivot rows",
        ["Pickup borough", "Pickup zone", "Date period", "Day period"],
        key="pivot_row",
    )
    pivot_measure = st.selectbox(
        "Pivot measure",
        ["Revenue", "Trip count", "Tips"],
        key="pivot_measure",
    )

    pivot_rows = {
        "Pickup borough": ("lpu.borough", "pickup_borough"),
        "Pickup zone": ("lpu.zone_name", "pickup_zone"),
        "Date period": (group_expr, group_label),
        "Day period": ("tm.day_period", "day_period"),
    }
    pivot_measures = {
        "Revenue": ("SUM(f.total_amount)", "revenue"),
        "Trip count": ("COUNT(*)", "trip_count"),
        "Tips": ("SUM(f.tip_amount)", "tips"),
    }
    pivot_row_expr, pivot_row_label = pivot_rows[pivot_row]
    pivot_measure_expr, pivot_measure_label = pivot_measures[pivot_measure]
    pivot_sql = f"""
    SELECT
        {pivot_row_expr} AS row_value,
        p.payment_category AS column_value,
        COALESCE({pivot_measure_expr}, 0) AS measure_value
    FROM fact_trip f
    JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
    JOIN dim_time tm ON tm.time_key = f.pickup_time_key
    JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
    JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
    WHERE {FILTERS}
    GROUP BY {pivot_row_expr}, p.payment_category
    ORDER BY {pivot_row_expr}, p.payment_category
    """
    pivot_data = read_df(pivot_sql, params)
    if pivot_data.empty:
        st.info("No records match the selected filters.")
    else:
        pivot_table = pivot_data.pivot_table(
            index="row_value",
            columns="column_value",
            values="measure_value",
            aggfunc="sum",
            fill_value=0,
        ).reset_index()
        pivot_table.columns.name = None
        pivot_table = pivot_table.rename(columns={"row_value": pivot_row_label})
        st.dataframe(pivot_table, use_container_width=True, hide_index=True)
        st.bar_chart(pivot_table.set_index(pivot_row_label))
        st.download_button(
            "Download pivot results (CSV)",
            pivot_table.to_csv(index=False).encode("utf-8"),
            "pivot_analysis.csv",
            "text/csv",
        )

st.divider()
st.caption(
    "This dashboard reads from the existing nyc_taxi_dw warehouse. "
    "It does not create or modify warehouse tables."
)
