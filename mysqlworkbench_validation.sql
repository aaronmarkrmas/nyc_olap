-- STADVDB MCO1 Step 4
-- MySQL Workbench validation script for the NYC Taxi OLAP dashboard.
--
-- Run this after Step 3 has populated nyc_taxi_dw.
-- Each section prints a result set that can be compared with the matching
-- dashboard table after selecting the same controls and clicking Apply filters.
-- The script is read-only: it only creates and drops a temporary test table.

USE nyc_taxi_dw;

SET @start_date = '2024-06-01';
SET @end_date = '2024-06-30';
SET @borough = 'All boroughs';
SET @payment_category = 'All payment categories';

-- These choose valid values from the warehouse so the script does not depend
-- on a hard-coded spelling or on a particular dimension load order.
SET @test_borough = (
    SELECT borough
    FROM dim_location
    WHERE borough IS NOT NULL AND TRIM(borough) <> ''
    ORDER BY borough
    LIMIT 1
);
SET @test_payment_category = (
    SELECT payment_category
    FROM dim_payment_type
    WHERE payment_category IS NOT NULL AND TRIM(payment_category) <> ''
    ORDER BY payment_category
    LIMIT 1
);

DROP TEMPORARY TABLE IF EXISTS olap_test_results;
CREATE TEMPORARY TABLE olap_test_results (
    test_id VARCHAR(10) NOT NULL,
    test_name VARCHAR(100) NOT NULL,
    actual_value DECIMAL(20, 4) NULL,
    expected_value DECIMAL(20, 4) NULL,
    status VARCHAR(4) NOT NULL
);

-- ============================================================================
-- T01: Global KPI baseline
-- Dashboard: Apply filters = Jun 1-30, All boroughs, All payment categories.
-- ============================================================================
SELECT 'T01 - KPI baseline' AS test_case;
SELECT
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS total_revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance,
    COALESCE(SUM(f.tip_amount), 0) AS total_tips
FROM fact_trip f
WHERE f.pickup_date_key BETWEEN
      CAST(DATE_FORMAT(@start_date, '%Y%m%d') AS UNSIGNED)
      AND CAST(DATE_FORMAT(@end_date, '%Y%m%d') AS UNSIGNED);

-- ============================================================================
-- T02: Slice by pickup borough
-- Dashboard: Keep dates/payment unchanged; set Pickup borough = @test_borough.
-- ============================================================================
SET @borough = @test_borough;
SELECT 'T02 - Borough slice' AS test_case, @borough AS selected_borough;
SELECT
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS total_revenue,
    COALESCE(SUM(f.tip_amount), 0) AS total_tips
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
  AND lpu.borough = @borough
  AND (@payment_category = 'All payment categories'
       OR p.payment_category = @payment_category);

-- Restore the all-borough setting for the next tests.
SET @borough = 'All boroughs';

-- ============================================================================
-- T03: Dice by borough and payment category
-- Dashboard: Set Pickup borough = @test_borough and Payment category =
-- @test_payment_category, then click Apply filters.
-- ============================================================================
SET @borough = @test_borough;
SET @payment_category = @test_payment_category;
SELECT
    'T03 - Borough and payment dice' AS test_case,
    @borough AS selected_borough,
    @payment_category AS selected_payment_category;
SELECT
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS total_revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance,
    COALESCE(SUM(f.tip_amount), 0) AS total_tips
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
  AND lpu.borough = @borough
  AND p.payment_category = @payment_category;

-- ============================================================================
-- T04: Date hierarchy roll-up/drill-down
-- Dashboard: Use All boroughs/All payment categories. Run the trend report
-- with Date hierarchy level = Day, Month, Quarter, and Year.
-- ============================================================================
SET @borough = 'All boroughs';
SET @payment_category = 'All payment categories';
SELECT 'T04A - Trend by day' AS test_case;
SELECT
    DATE_FORMAT(dpu.full_date, '%Y-%m-%d') AS period,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(SUM(f.tip_amount), 0) AS tips,
    COALESCE(AVG(f.total_amount), 0) AS avg_fare_total
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY DATE_FORMAT(dpu.full_date, '%Y-%m-%d')
ORDER BY MIN(dpu.full_date);

SELECT 'T04B - Trend rolled up to month' AS test_case;
SELECT
    DATE_FORMAT(dpu.full_date, '%Y-%m') AS period,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(SUM(f.tip_amount), 0) AS tips,
    COALESCE(AVG(f.total_amount), 0) AS avg_fare_total
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY DATE_FORMAT(dpu.full_date, '%Y-%m')
ORDER BY MIN(dpu.full_date);

SELECT 'T04C - Trend rolled up to quarter' AS test_case;
SELECT
    CONCAT(YEAR(dpu.full_date), '-Q', QUARTER(dpu.full_date)) AS period,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(SUM(f.tip_amount), 0) AS tips,
    COALESCE(AVG(f.total_amount), 0) AS avg_fare_total
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY YEAR(dpu.full_date), QUARTER(dpu.full_date)
ORDER BY MIN(dpu.full_date);

SELECT 'T04D - Trend rolled up to year' AS test_case;
SELECT
    CAST(YEAR(dpu.full_date) AS CHAR) AS period,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(SUM(f.tip_amount), 0) AS tips,
    COALESCE(AVG(f.total_amount), 0) AS avg_fare_total
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY YEAR(dpu.full_date)
ORDER BY MIN(dpu.full_date);

-- ============================================================================
-- T05: Location hierarchy and role
-- Dashboard: Location level = Borough, then Zone; repeat for Pickup and
-- Drop-off. The global borough filter remains a pickup-borough filter.
-- ============================================================================
SELECT 'T05A - Pickup rolled up by borough' AS test_case;
SELECT
    lpu.borough,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance_mi
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY lpu.borough
ORDER BY trip_count DESC
LIMIT 25;

SELECT 'T05B - Pickup drilled down to borough and zone' AS test_case;
SELECT
    lpu.borough,
    lpu.zone_name AS zone,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance_mi
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY lpu.borough, lpu.zone_name
ORDER BY trip_count DESC
LIMIT 25;

SELECT 'T05C - Drop-off drilled down to borough and zone' AS test_case;
SELECT
    loc.borough,
    loc.zone_name AS zone,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(AVG(f.trip_distance_mi), 0) AS avg_distance_mi
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_location loc ON loc.location_key = f.dropoff_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY loc.borough, loc.zone_name
ORDER BY trip_count DESC
LIMIT 25;

-- ============================================================================
-- T06: Time hierarchy
-- Dashboard: Time grouping = Day period, then Hour of day.
-- ============================================================================
SELECT 'T06A - Time grouped by day period' AS test_case;
SELECT
    tm.day_period AS time_bucket,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(AVG(f.trip_duration_sec) / 60, 0) AS avg_duration_minutes
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_time tm ON tm.time_key = f.pickup_time_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY tm.day_period
ORDER BY MIN(tm.day_period_order);

SELECT 'T06B - Time drilled down to hour' AS test_case;
SELECT
    tm.hour_24 AS time_bucket,
    COUNT(*) AS trip_count,
    COALESCE(SUM(f.total_amount), 0) AS revenue,
    COALESCE(AVG(f.trip_duration_sec) / 60, 0) AS avg_duration_minutes
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_time tm ON tm.time_key = f.pickup_time_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY tm.hour_24
ORDER BY tm.hour_24;

-- ============================================================================
-- T07: Pivot
-- Dashboard: Pivot rows = Pickup borough; Pivot measure = Revenue.
-- The dashboard pivots payment_category into columns after this same grouped
-- result is returned.
-- ============================================================================
SELECT 'T07 - Pivot by pickup borough and payment category' AS test_case;
SELECT
    lpu.borough AS row_value,
    p.payment_category AS column_value,
    COALESCE(SUM(f.total_amount), 0) AS measure_value
FROM fact_trip f
JOIN dim_date dpu ON dpu.date_key = f.pickup_date_key
JOIN dim_time tm ON tm.time_key = f.pickup_time_key
JOIN dim_location lpu ON lpu.location_key = f.pickup_location_key
JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE dpu.full_date BETWEEN @start_date AND @end_date
GROUP BY lpu.borough, p.payment_category
ORDER BY lpu.borough, p.payment_category;

-- ============================================================================
-- T08: Automated correctness checks
-- These checks validate invariants that should hold for any correctly loaded
-- warehouse, without hard-coding the current dataset's aggregate values.
-- ============================================================================
SET @borough = 'All boroughs';
SET @payment_category = 'All payment categories';

INSERT INTO olap_test_results
SELECT
    'T08A',
    'Trip count equals sum of daily trend counts',
    (SELECT COUNT(*)
     FROM fact_trip f
     JOIN dim_date d ON d.date_key = f.pickup_date_key
     WHERE d.full_date BETWEEN @start_date AND @end_date),
    (SELECT COALESCE(SUM(day_counts.trip_count), 0)
     FROM (
         SELECT COUNT(*) AS trip_count
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         WHERE d.full_date BETWEEN @start_date AND @end_date
         GROUP BY d.full_date
     ) AS day_counts),
    CASE WHEN
        (SELECT COUNT(*)
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         WHERE d.full_date BETWEEN @start_date AND @end_date)
        =
        (SELECT COALESCE(SUM(day_counts.trip_count), 0)
         FROM (
             SELECT COUNT(*) AS trip_count
             FROM fact_trip f
             JOIN dim_date d ON d.date_key = f.pickup_date_key
             WHERE d.full_date BETWEEN @start_date AND @end_date
             GROUP BY d.full_date
         ) AS day_counts)
    THEN 'PASS' ELSE 'FAIL' END;

INSERT INTO olap_test_results
SELECT
    'T08B',
    'Borough slice cannot exceed all-borough count',
    (SELECT COUNT(*)
     FROM fact_trip f
     JOIN dim_date d ON d.date_key = f.pickup_date_key
     JOIN dim_location l ON l.location_key = f.pickup_location_key
     WHERE d.full_date BETWEEN @start_date AND @end_date
       AND l.borough = @test_borough),
    (SELECT COUNT(*)
     FROM fact_trip f
     JOIN dim_date d ON d.date_key = f.pickup_date_key
     WHERE d.full_date BETWEEN @start_date AND @end_date),
    CASE WHEN
        (SELECT COUNT(*)
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         JOIN dim_location l ON l.location_key = f.pickup_location_key
         WHERE d.full_date BETWEEN @start_date AND @end_date
           AND l.borough = @test_borough)
        <=
        (SELECT COUNT(*)
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         WHERE d.full_date BETWEEN @start_date AND @end_date)
    THEN 'PASS' ELSE 'FAIL' END;

INSERT INTO olap_test_results
SELECT
    'T08C',
    'Revenue pivot total equals unpivoted revenue total',
    (SELECT COALESCE(SUM(f.total_amount), 0)
     FROM fact_trip f
     JOIN dim_date d ON d.date_key = f.pickup_date_key
     WHERE d.full_date BETWEEN @start_date AND @end_date),
    (SELECT COALESCE(SUM(pivot_values.measure_value), 0)
     FROM (
         SELECT
             l.borough,
             p.payment_category,
             SUM(f.total_amount) AS measure_value
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         JOIN dim_location l ON l.location_key = f.pickup_location_key
         JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
         WHERE d.full_date BETWEEN @start_date AND @end_date
         GROUP BY l.borough, p.payment_category
     ) AS pivot_values),
    CASE WHEN ABS(
        (SELECT COALESCE(SUM(f.total_amount), 0)
         FROM fact_trip f
         JOIN dim_date d ON d.date_key = f.pickup_date_key
         WHERE d.full_date BETWEEN @start_date AND @end_date)
        -
        (SELECT COALESCE(SUM(pivot_values.measure_value), 0)
         FROM (
             SELECT
                 l.borough,
                 p.payment_category,
                 SUM(f.total_amount) AS measure_value
             FROM fact_trip f
             JOIN dim_date d ON d.date_key = f.pickup_date_key
             JOIN dim_location l ON l.location_key = f.pickup_location_key
             JOIN dim_payment_type p ON p.payment_type_key = f.payment_type_key
             WHERE d.full_date BETWEEN @start_date AND @end_date
             GROUP BY l.borough, p.payment_category
         ) AS pivot_values)
    ) < 0.01 THEN 'PASS' ELSE 'FAIL' END;

SELECT
    test_id,
    test_name,
    actual_value,
    expected_value,
    status
FROM olap_test_results
ORDER BY test_id;

SELECT
    COUNT(*) AS total_checks,
    SUM(status = 'PASS') AS passed_checks,
    SUM(status = 'FAIL') AS failed_checks
FROM olap_test_results;
