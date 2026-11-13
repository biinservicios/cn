-- =====================================================================================
-- Compensacion Variable -> Databricks: discovery v1
-- Run each query on its own, the SAME DAY for SQL Server and Databricks (D4 vs L2 compares the current month).
-- Databricks part: Panama warehouse (brewdat-maz-sales-pa-adb-ep01-p). Paste me all results.
-- =====================================================================================


-- =====================================================================================
-- SQL SERVER
-- =====================================================================================

-- L1. DSR_M_2018_Reloaded: 5 sample Hls rows, all columns (to see what Mes / MesMetaTotal / Ruta are)
SELECT TOP 5 * FROM WarehousePanama.dbo.DSR_M_2018_Reloaded WHERE [KPI] = 'Hls';

-- L2. Current-month totals the report uses: by Region + Categoria + Category Group (compare with D4)
SELECT [Región], [Categoria], [Category Group],
       COUNT(DISTINCT [Ruta]) AS rutas, SUM([Mes]) AS mes_hl, SUM([MesMetaTotal]) AS meta_hl
FROM WarehousePanama.dbo.DSR_M_2018_Reloaded
WHERE [KPI] = 'Hls'
GROUP BY [Región], [Categoria], [Category Group]
ORDER BY [Región], [Categoria], [Category Group];

-- L3. Balboa Dorada by Region (the only Brand-Local KPI)
SELECT [Región], COUNT(DISTINCT [Ruta]) AS rutas, SUM([Mes]) AS mes_hl, SUM([MesMetaTotal]) AS meta_hl
FROM WarehousePanama.dbo.DSR_M_2018_Reloaded
WHERE [KPI] = 'Hls' AND [Brand-Local] = 'Balboa Dorada'
GROUP BY [Región]
ORDER BY [Región];

-- L4. HistoricosPanama monthly tables used by "Cobertura Beer VIP": 5 rows + size
SELECT TOP 5 * FROM HistoricosPanama.dbo.[2026_10];
SELECT COUNT(*) AS filas, COUNT(DISTINCT [Customer Code]) AS clientes, SUM([Sales Volume (HL) - BIL]) AS hl
FROM HistoricosPanama.dbo.[2026_10];


-- =====================================================================================
-- DATABRICKS
-- =====================================================================================

-- D1. BEES visits / tasks: can this warehouse read them, and how many PA rows (all history vs. since last month)
SELECT 'visit' AS t, COUNT(*) AS filas_pa,
       SUM(CASE WHEN visit_date >= add_months(trunc(current_date(), 'MM'), -1) THEN 1 ELSE 0 END) AS desde_mes_anterior,
       MIN(visit_date) AS desde, MAX(visit_date) AS hasta
FROM brewdat_uc_maz_bees_1p_ds.frt_nickel.external__sharing_visit
WHERE country = 'PA'
UNION ALL
SELECT 'task', COUNT(*),
       SUM(CASE WHEN task_end_date >= add_months(trunc(current_date(), 'MM'), -1) THEN 1 ELSE 0 END),
       MIN(task_end_date), MAX(task_end_date)
FROM brewdat_uc_maz_bees_1p_ds.frt_nickel.external__sharing_task
WHERE country = 'PA';

-- D2. Region / Gerencia values in the manual hierarchy (exact spelling: "ON VIP" vs "ON Vip", "K.A", ...)
SELECT region_name, commercial_management_name, COUNT(*) AS filas
FROM brewdat_uc_maz_prod.slv_maz_masterdata_manual.pa_client_commercial_management_hierarchy
GROUP BY 1, 2
ORDER BY 1, 2;

-- D3. Quota table: which months are loaded
SELECT reference_year, reference_month, COUNT(*) AS filas, SUM(CAST(target_hl AS DOUBLE)) AS cuota_hl
FROM brewdat_uc_maz_prod.brz_maz_sales_manual.pa_sales_target_customer_material_current_month
GROUP BY 1, 2
ORDER BY 1 DESC, 2 DESC
LIMIT 6;

-- D4. The proposed replacement of DSR_M_2018_Reloaded (current month, HL): compare with L2
WITH c AS (
    SELECT regexp_replace(trim(CAST(customer_short_code AS STRING)), '^0+', '') AS cliente, sales_zone_code AS ruta,
           trim(CAST(sales_subregion_code AS STRING)) AS subregion,
           ROW_NUMBER() OVER (PARTITION BY regexp_replace(trim(CAST(customer_short_code AS STRING)), '^0+', '')
                              ORDER BY CASE WHEN customer_status = 'Active' THEN 0 ELSE 1 END,
                                       customer_updated_at DESC, sales_organization_code DESC) AS rn
    FROM brewdat_uc_delta_maz_prod.gld_maz_masterdata_sales.pa_customer
    WHERE country_code = 'PA'
),
h AS (
    SELECT trim(CAST(customer_group_code AS STRING)) AS k, region_name,
           ROW_NUMBER() OVER (PARTITION BY trim(CAST(customer_group_code AS STRING)) ORDER BY region_name) AS rn
    FROM brewdat_uc_maz_prod.slv_maz_masterdata_manual.pa_client_commercial_management_hierarchy
),
cli AS (
    SELECT c.cliente, c.ruta, COALESCE(h.region_name, CASE WHEN c.subregion = '90' THEN 'Cliente Interno' END) AS region
    FROM c LEFT JOIN h ON h.k = c.subregion AND h.rn = 1
    WHERE c.rn = 1
),
m AS (
    SELECT material, product_category, category_group, brand_local
    FROM (SELECT regexp_replace(trim(CAST(sku AS STRING)), '^0+', '') AS material, product_category, category_group, brand_local,
                 ROW_NUMBER() OVER (PARTITION BY regexp_replace(trim(CAST(sku AS STRING)), '^0+', '') ORDER BY date_since DESC) AS rn
          FROM brewdat_uc_delta_maz_prod.slv_maz_masterdata_manual.pa_excise_rules) t
    WHERE rn = 1
),
v AS (
    SELECT regexp_replace(CAST(sold_to_customer_short_code AS STRING), '^0+', '') AS cliente,
           regexp_replace(CAST(product_short_code AS STRING), '^0+', '') AS material,
           SUM(total_volume) AS hl
    FROM brewdat_uc_delta_maz_prod.gld_maz_sales_sell_in.pa_invoice
    WHERE invoice_date >= trunc(current_date(), 'MM') AND invoice_date < add_months(trunc(current_date(), 'MM'), 1)
      AND (op_ind IS NULL OR op_ind NOT IN ('D', 'DELETE'))
    GROUP BY 1, 2
),
q AS (
    SELECT regexp_replace(trim(CAST(customer_code AS STRING)), '^0+', '') AS cliente,
           regexp_replace(trim(CAST(product_short_code AS STRING)), '^0+', '') AS material,
           SUM(CAST(target_hl AS DOUBLE)) AS meta
    FROM brewdat_uc_maz_prod.brz_maz_sales_manual.pa_sales_target_customer_material_current_month
    WHERE CAST(reference_year AS INT) = year(current_date()) AND CAST(reference_month AS INT) = month(current_date())
    GROUP BY 1, 2
),
x AS (
    SELECT COALESCE(v.cliente, q.cliente) AS cliente, COALESCE(v.material, q.material) AS material,
           COALESCE(v.hl, 0) AS hl, COALESCE(q.meta, 0) AS meta
    FROM v FULL OUTER JOIN q ON q.cliente = v.cliente AND q.material = v.material
)
SELECT cli.region,
       CASE WHEN m.product_category IN ('CSD', 'Malt') THEN 'NABs' ELSE m.product_category END AS categoria,
       m.category_group,
       COUNT(DISTINCT cli.ruta) AS rutas, ROUND(SUM(x.hl), 2) AS mes_hl, ROUND(SUM(x.meta), 2) AS meta_hl,
       ROUND(SUM(CASE WHEN m.brand_local = 'Balboa Dorada' THEN x.hl ELSE 0 END), 2) AS balboa_dorada_hl,
       ROUND(SUM(CASE WHEN m.brand_local = 'Balboa Dorada' THEN x.meta ELSE 0 END), 2) AS balboa_dorada_meta
FROM x
LEFT JOIN cli ON cli.cliente = x.cliente
LEFT JOIN m ON m.material = x.material
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
