
-- creating view to select specific columns and narrow the dates down to recent 6 months --
CREATE VIEW sales_view AS
SELECT 
    Product_ID,
    Product_Category,
    Sale_Date,
    DATENAME (MONTH, Sale_Date) AS Month,
    MONTH(Sale_Date) AS MonthNum,
    YEAR(Sale_Date) AS Year,
    Quantity_Sold,
    Sales_Amount
FROM sales
WHERE Sale_Date >= DATEADD(MONTH, -6, (SELECT MAX(Sale_Date) FROM sales))

-- creating view to see each month's total of quantity sold -- 
CREATE VIEW Monthly_Total AS
SELECT 
    Product_ID,
    Month,
    MonthNum,
    SUM(Quantity_Sold) as Monthly_Total
FROM sales_view
GROUP BY
    Product_ID,
    Month,
    MonthNum

-- calculating 3 months Moving Average to forecast quantity demand --
CREATE VIEW MovingAvg_Forecast AS
SELECT *,
    AVG(Monthly_Total) OVER (PARTITION BY Product_ID ORDER BY MonthNum DESC
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvg_Forecast
FROM Monthly_Total

-- calculating Exponential Smoothing to forecast quantity demand -- 

-- устанавливаем переменную/это коэфициент сглаживания --
DECLARE @alpha FLOAT = 0.3; 

-- подготавливаем данные/ добавляем нумерацию строк --
WITH SalesData AS
(
SELECT 
    Product_ID,
    Month,
    MonthNum,
    SUM(Quantity_Sold) AS Monthly_Total,
    ROW_NUMBER() OVER (
        PARTITION BY Product_ID
        ORDER BY MonthNum
    ) AS rn
FROM sales_view
GROUP BY 
    Product_ID,
    Month,
    MonthNum
),
-- используем первый месяц как старт/фактические продажи --
ExpSmooth AS
(
SELECT
    Product_ID,
    Month,
    MonthNum,
    Monthly_Total,
    rn,
    CAST(ROUND(Monthly_Total,2) AS FLOAT) AS ExpSmooth_Forecast
FROM SalesData
WHERE rn = 1

UNION ALL
-- решаем по формуле экспоненционального сглаживания --
SELECT
    s.Product_ID,
    s.Month,
    s.MonthNum,
    s.Monthly_Total,
    s.rn,
    (@alpha * s.Monthly_Total)
    + ((1 - @alpha) * e.ExpSmooth_Forecast) AS Forecast
FROM SalesData s
JOIN ExpSmooth e
    ON s.Product_ID = e.Product_ID
    AND s.rn = e.rn + 1
)
SELECT *
FROM ExpSmooth
ORDER BY Product_ID, MonthNum
OPTION (MAXRECURSION 0)

-- ABC Analysis --

WITH product_sales AS (
    SELECT
        Product_ID,
        SUM(Sales_Amount) AS total_sales
    FROM sales
    GROUP BY Product_ID
),

sales_share AS (
    SELECT
        Product_ID,
        total_sales,
        total_sales * 100.0 / SUM(total_sales) OVER () AS sales_percent
    FROM product_sales
),

cumulative AS (
    SELECT
        Product_ID,
        total_sales,
        sales_percent,
        SUM(sales_percent) OVER (ORDER BY total_sales DESC) AS cumulative_percent
    FROM sales_share
)
SELECT
    Product_ID,
    total_sales,
    ROUND(sales_percent,2) AS sales_percent,
    ROUND(cumulative_percent,2) AS cumulative_percent,
    CASE
        WHEN cumulative_percent <= 80 THEN 'A'
        WHEN cumulative_percent <= 95 THEN 'B'
        ELSE 'C'
    END AS abc_class

FROM cumulative
ORDER BY total_sales DESC

