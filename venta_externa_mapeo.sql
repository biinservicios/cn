-- =====================================================================================
-- Venta Externa - field mapping before building the Power BI
-- Legacy: SAP query (Sociedad CO 0600, account S413101AT0) -> dbo.Venta_Externa -> Alteryx -> dbo.venta_exportacion
-- VE1 / VE2 in SQL Server, VE3 / VE4 in Databricks. Same month (October 2026) so the rows can be matched
-- by invoice + position. Paste me the 4 results.
-- =====================================================================================


-- =====================================================================================
-- VE1. SQL SERVER - raw SAP extract, 20 lines of October 2026, all columns
-- =====================================================================================
SELECT TOP 20 *
FROM WarehousePanama.dbo.Venta_Externa
WHERE [Fe.contab.] LIKE '2026.10.%'
ORDER BY [Factura], [Pos.];


-- =====================================================================================
-- VE2. SQL SERVER - Alteryx output by month (what the report shows today)
-- =====================================================================================
SELECT [mes], COUNT(*) AS lineas, SUM([Volumen]) AS volumen, SUM([Importe]) AS importe,
       MIN([Fe.Contab.]) AS desde, MAX([Fe.Contab.]) AS hasta
FROM WarehousePanama.dbo.venta_exportacion
GROUP BY [mes]
ORDER BY [mes];


-- =====================================================================================
-- VE3. DATABRICKS - the same account in SAP silver, October 2026, 20 lines with every GLPCA column
--      plus the invoice fields the SAP query shows (quantity, unit, volume, material, sales doc, ...)
-- =====================================================================================
WITH g AS (
  SELECT *
  FROM brewdat_uc_delta_maz_prod.slv_maz_finance_sap_pr3.copecac_glpca
  WHERE racct = 'S413101AT0'
    AND budat BETWEEN '2026-10-01' AND '2026-10-31'
)
SELECT g.*,
       p.fkimg  AS vbrp_fkimg,  p.vrkme AS vbrp_vrkme, p.volum AS vbrp_volum, p.voleh AS vbrp_voleh,
       p.netwr  AS vbrp_netwr,  p.aubel AS vbrp_aubel, p.matnr AS vbrp_matnr, p.pstyv AS vbrp_pstyv,
       p.vkaus  AS vbrp_vkaus,
       k.fkart  AS vbrk_fkart,  k.fkdat AS vbrk_fkdat, k.kunrg AS vbrk_kunrg, k.kunag AS vbrk_kunag,
       k.bukrs  AS vbrk_bukrs
FROM g
LEFT JOIN brewdat_uc_delta_maz_prod.slv_maz_sales_sap_pr3.copecac_vbrp p
  ON p.vbeln = g.refdocnr AND p.posnr = g.posnr
LEFT JOIN brewdat_uc_delta_maz_prod.slv_maz_sales_sap_pr3.copecac_vbrk k
  ON k.vbeln = g.refdocnr
ORDER BY g.refdocnr, g.posnr
LIMIT 20;


-- =====================================================================================
-- VE4. DATABRICKS - the same account by month, 2026 (to compare with VE2)
-- =====================================================================================
SELECT month(budat)                    AS mes,
       rbukrs                          AS sociedad,
       COUNT(*)                        AS lineas,
       ROUND(-SUM(hsl), 2)             AS importe_hsl,
       MIN(budat)                      AS desde,
       MAX(budat)                      AS hasta
FROM brewdat_uc_delta_maz_prod.slv_maz_finance_sap_pr3.copecac_glpca
WHERE racct = 'S413101AT0'
  AND budat BETWEEN '2026-01-01' AND '2026-11-30'
GROUP BY 1, 2
ORDER BY 1, 2;
