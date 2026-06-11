-- =====================================================================
-- TEST 1: Compare raw byte size — NVARCHAR vs JSON in memory
-- =====================================================================

DECLARE @json_text NVARCHAR(MAX) = N'{
    "OrderID": 1001,
    "Customer": "John Smith",
    "Email": "john@example.com",
    "Items": [
        {"Product": "Widget A", "Qty": 2, "Price": 19.99},
        {"Product": "Widget B", "Qty": 1, "Price": 49.99}
    ],
    "Total": 89.97,
    "Status": "Shipped"
}';

SELECT
    LEN(@json_text)                     AS [Character Length],
    DATALENGTH(@json_text)              AS [NVARCHAR Bytes (UTF-16)],
    DATALENGTH(@json_text) / 2          AS [Approx UTF-8 Bytes],
    DATALENGTH(CAST(@json_text AS JSON)) AS [Native JSON Bytes]  -- SQL 2025 only


-- =====================================================================
-- TEST 2: Create both table types and compare actual storage on disk
-- =====================================================================

-- Table using NVARCHAR (old approach)
CREATE TABLE dbo.Orders_NVARCHAR (
    OrderID     INT IDENTITY PRIMARY KEY,
    OrderDetail NVARCHAR(MAX)
);

-- Table using native JSON (SQL Server 2025+)
CREATE TABLE dbo.Orders_JSON (
    OrderID     INT IDENTITY PRIMARY KEY,
    OrderDetail JSON NOT NULL
);

-- Insert same 100,000 rows into both
INSERT INTO dbo.Orders_NVARCHAR (OrderDetail)
SELECT TOP 100000
    N'{"OrderID":' + CAST(ROW_NUMBER() OVER (ORDER BY a.object_id) AS NVARCHAR)
    + ',"Customer":"John Smith"'
    + ',"Email":"john.smith@example.com"'
    + ',"Address":{"Line1":"123 High Street","City":"London","Postcode":"SW1A 1AA"}'
    + ',"Items":[{"Code":"PROD001","Desc":"Blue Widget","Qty":3,"Price":19.99},'
    + '{"Code":"PROD002","Desc":"Red Gadget","Qty":1,"Price":74.99}]'
    + ',"Total":134.96,"Currency":"GBP","Status":"Shipped"}'
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

INSERT INTO dbo.Orders_JSON (OrderDetail)
SELECT TOP 100000
    N'{"OrderID":' + CAST(ROW_NUMBER() OVER (ORDER BY a.object_id) AS NVARCHAR)
    + ',"Customer":"John Smith"'
    + ',"Email":"john.smith@example.com"'
    + ',"Address":{"Line1":"123 High Street","City":"London","Postcode":"SW1A 1AA"}'
    + ',"Items":[{"Code":"PROD001","Desc":"Blue Widget","Qty":3,"Price":19.99},'
    + '{"Code":"PROD002","Desc":"Red Gadget","Qty":1,"Price":74.99}]'
    + ',"Total":134.96,"Currency":"GBP","Status":"Shipped"}'
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;

-- =====================================================================
-- TEST 3: Check actual disk space used by each table
-- =====================================================================

SELECT
    t.name                                              AS [Table],
    p.rows                                              AS [Row Count],
    CAST(SUM(a.total_pages)  * 8 / 1024.0 AS DECIMAL(18,2))
                                                        AS [Total Space MB],
    CAST(SUM(a.used_pages)   * 8 / 1024.0 AS DECIMAL(18,2))
                                                        AS [Used Space MB],
    CAST(SUM(a.data_pages)   * 8 / 1024.0 AS DECIMAL(18,2))
                                                        AS [Data Space MB],
    CAST(SUM(a.used_pages)   * 8 * 1024.0
        / NULLIF(p.rows, 0)   AS DECIMAL(18,2))
                                                        AS [Avg Bytes per Row]
FROM sys.tables              t
JOIN sys.indexes             i  ON i.object_id  = t.object_id
JOIN sys.partitions          p  ON p.object_id  = t.object_id
                                AND p.index_id  = i.index_id
JOIN sys.allocation_units    a  ON a.container_id = p.partition_id
WHERE t.name IN ('Orders_NVARCHAR', 'Orders_JSON')
  AND i.index_id <= 1
GROUP BY t.name, p.rows
ORDER BY t.name;


-- =====================================================================
-- TEST 4: Row-level size comparison (per record)
-- =====================================================================

SELECT TOP 10
    'NVARCHAR'                              AS [Storage Type],
    OrderID,
    DATALENGTH(OrderDetail)                 AS [Bytes per Row],
    CAST(DATALENGTH(OrderDetail) / 1024.0
        AS DECIMAL(10,2))                   AS [KB per Row]
FROM dbo.Orders_NVARCHAR

UNION ALL

SELECT TOP 10
    'JSON (Native)',
    OrderID,
    DATALENGTH(OrderDetail),
    CAST(DATALENGTH(OrderDetail) / 1024.0
        AS DECIMAL(10,2))
FROM dbo.Orders_JSON

ORDER BY [Storage Type], OrderID;


-- =====================================================================
-- CLEANUP Finally Tested successfully and to drop tables created
-- =====================================================================
--DROP TABLE dbo.Orders_NVARCHAR;
DROP TABLE dbo.Orders_JSON;
