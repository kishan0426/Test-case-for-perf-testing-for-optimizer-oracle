--------------------------------------------------------------------------------
-- ORACLE 23ai OPTIMIZER / TRACE LAB
--
-- Purpose:
--   10053  : Optimizer decisions / transformations / costing
--   10046  : SQL execution / waits / binds
--
-- Designed for:
--   Oracle Database 23ai
--
-- Run with:
--   SQL*Plus / SQLcl as a user able to:
--      - create tables/indexes
--      - execute DBMS_STATS
--      - alter session set events
--
-- Recommended:
--   SET SERVEROUTPUT ON
--   SET LINESIZE 250
--   SET PAGESIZE 100
--
-- Trace files are generated in the Oracle diagnostic destination.
-- Use:
--   SELECT value FROM v$diag_info WHERE name = 'Default Trace File';
--
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET LINESIZE 250
SET PAGESIZE 100
SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET TAB OFF
SET VERIFY OFF
SET FEEDBACK ON

ALTER SESSION SET statistics_level = ALL;

--------------------------------------------------------------------------------
-- 0. CLEANUP
--------------------------------------------------------------------------------

BEGIN
    FOR t IN (
        SELECT table_name
        FROM user_tables
        WHERE table_name IN (
            'OJ_DEPT',
            'OJ_EMP',
            'OJ_CUSTOMER',
            'OJ_ORDERS',
            'OJ_ORDER_ITEMS',
            'OJ_PRODUCT',
            'OJ_SALES',
            'OJ_BIG',
            'OJ_SMALL',
            'OJ_SKEW'
        )
    )
    LOOP
        BEGIN
            EXECUTE IMMEDIATE
                'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

--------------------------------------------------------------------------------
-- 1. BASE TABLES
--------------------------------------------------------------------------------

CREATE TABLE oj_dept (
    dept_id       NUMBER PRIMARY KEY,
    dept_name     VARCHAR2(100),
    region        VARCHAR2(30)
);

CREATE TABLE oj_emp (
    emp_id        NUMBER PRIMARY KEY,
    dept_id       NUMBER,
    emp_name      VARCHAR2(100),
    job           VARCHAR2(50),
    salary        NUMBER,
    hire_date     DATE,
    status        VARCHAR2(20)
);

CREATE TABLE oj_customer (
    customer_id   NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100),
    region        VARCHAR2(30),
    customer_type VARCHAR2(20),
    status        VARCHAR2(20)
);

CREATE TABLE oj_orders (
    order_id      NUMBER PRIMARY KEY,
    customer_id   NUMBER,
    order_date    DATE,
    status        VARCHAR2(20),
    amount        NUMBER
);

CREATE TABLE oj_order_items (
    order_id      NUMBER,
    line_id       NUMBER,
    product_id    NUMBER,
    quantity      NUMBER,
    price         NUMBER,
    CONSTRAINT oj_order_items_pk PRIMARY KEY(order_id,line_id)
);

CREATE TABLE oj_product (
    product_id    NUMBER PRIMARY KEY,
    product_name  VARCHAR2(100),
    category      VARCHAR2(30),
    price         NUMBER
);

--------------------------------------------------------------------------------
-- Tables for specific optimizer pathologies
--------------------------------------------------------------------------------

CREATE TABLE oj_sales (
    sale_id       NUMBER PRIMARY KEY,
    customer_id   NUMBER,
    sale_date     DATE,
    region        VARCHAR2(30),
    product_id    NUMBER,
    amount        NUMBER,
    flag          VARCHAR2(1)
);

CREATE TABLE oj_big (
    id            NUMBER PRIMARY KEY,
    group_id      NUMBER,
    payload       VARCHAR2(100)
);

CREATE TABLE oj_small (
    id            NUMBER PRIMARY KEY,
    group_id      NUMBER,
    payload       VARCHAR2(100)
);

CREATE TABLE oj_skew (
    id            NUMBER PRIMARY KEY,
    skew_col      NUMBER,
    payload       VARCHAR2(100)
);

--------------------------------------------------------------------------------
-- 2. DATA GENERATION
--------------------------------------------------------------------------------

BEGIN
    --------------------------------------------------------------------------
    -- Departments
    --------------------------------------------------------------------------
    INSERT INTO oj_dept
    SELECT level,
           'DEPT_' || level,
           CASE MOD(level,4)
             WHEN 0 THEN 'NORTH'
             WHEN 1 THEN 'SOUTH'
             WHEN 2 THEN 'EAST'
             ELSE 'WEST'
           END
    FROM dual
    CONNECT BY level <= 100;


    --------------------------------------------------------------------------
    -- Employees: 100,000 rows
    --------------------------------------------------------------------------
    INSERT INTO oj_emp
    SELECT level,
           MOD(level,100) + 1,
           'EMP_' || level,
           CASE MOD(level,5)
             WHEN 0 THEN 'MANAGER'
             WHEN 1 THEN 'ENGINEER'
             WHEN 2 THEN 'ANALYST'
             WHEN 3 THEN 'CLERK'
             ELSE 'SALES'
           END,
           30000 + MOD(level * 7919,120000),
           DATE '2015-01-01' + MOD(level,3500),
           CASE
             WHEN MOD(level,20) = 0 THEN 'INACTIVE'
             ELSE 'ACTIVE'
           END
    FROM dual
    CONNECT BY level <= 100000;


    --------------------------------------------------------------------------
    -- Customers: 50,000
    --------------------------------------------------------------------------
    INSERT INTO oj_customer
    SELECT level,
           'CUSTOMER_' || level,
           CASE MOD(level,5)
             WHEN 0 THEN 'NORTH'
             WHEN 1 THEN 'SOUTH'
             WHEN 2 THEN 'EAST'
             WHEN 3 THEN 'WEST'
             ELSE 'CENTRAL'
           END,
           CASE MOD(level,10)
             WHEN 0 THEN 'VIP'
             WHEN 1 THEN 'VIP'
             ELSE 'STANDARD'
           END,
           CASE
             WHEN MOD(level,25)=0 THEN 'INACTIVE'
             ELSE 'ACTIVE'
           END
    FROM dual
    CONNECT BY level <= 50000;


    --------------------------------------------------------------------------
    -- Products
    --------------------------------------------------------------------------
    INSERT INTO oj_product
    SELECT level,
           'PRODUCT_' || level,
           CASE MOD(level,6)
             WHEN 0 THEN 'ELECTRONICS'
             WHEN 1 THEN 'BOOKS'
             WHEN 2 THEN 'HOME'
             WHEN 3 THEN 'SPORTS'
             WHEN 4 THEN 'OFFICE'
             ELSE 'OTHER'
           END,
           10 + MOD(level * 37,1000)
    FROM dual
    CONNECT BY level <= 1000;


    --------------------------------------------------------------------------
    -- Orders: 500,000
    --------------------------------------------------------------------------
    INSERT INTO oj_orders
    SELECT level,
           MOD(level * 13,50000) + 1,
           DATE '2024-01-01' + MOD(level,700),
           CASE MOD(level,10)
             WHEN 0 THEN 'CANCELLED'
             WHEN 1 THEN 'PENDING'
             ELSE 'COMPLETE'
           END,
           10 + MOD(level * 97,10000)
    FROM dual
    CONNECT BY level <= 500000;


    --------------------------------------------------------------------------
    -- Order items: 1.5M
    --------------------------------------------------------------------------
    INSERT INTO oj_order_items
    SELECT o.order_id,
           x.line_id,
           MOD(o.order_id * 17 + x.line_id * 31,1000) + 1,
           MOD(o.order_id + x.line_id,10) + 1,
           10 + MOD(o.order_id * 13 + x.line_id * 7,1000)
    FROM oj_orders o
    CROSS JOIN (
        SELECT level line_id
        FROM dual
        CONNECT BY level <= 3
    ) x;


    --------------------------------------------------------------------------
    -- Sales: 1M rows
    --------------------------------------------------------------------------
    INSERT INTO oj_sales
    SELECT level,
           MOD(level * 13,50000)+1,
           DATE '2024-01-01' + MOD(level,700),
           CASE MOD(level,5)
             WHEN 0 THEN 'NORTH'
             WHEN 1 THEN 'SOUTH'
             WHEN 2 THEN 'EAST'
             WHEN 3 THEN 'WEST'
             ELSE 'CENTRAL'
           END,
           MOD(level * 17,1000)+1,
           1 + MOD(level * 7919,5000),
           CASE
             WHEN MOD(level,100)=0 THEN 'Y'
             ELSE 'N'
           END
    FROM dual
    CONNECT BY level <= 1000000;


    --------------------------------------------------------------------------
    -- Big table: 1M rows
    --------------------------------------------------------------------------
    INSERT INTO oj_big
    SELECT level,
           MOD(level,10000),
           RPAD('BIG',100,'X')
    FROM dual
    CONNECT BY level <= 1000000;


    --------------------------------------------------------------------------
    -- Small table: 10,000 rows
    --------------------------------------------------------------------------
    INSERT INTO oj_small
    SELECT level,
           MOD(level,10000),
           RPAD('SMALL',100,'Y')
    FROM dual
    CONNECT BY level <= 10000;


    --------------------------------------------------------------------------
    -- Highly skewed table
    --
    -- 99% = 1
    -- 1%  = values 2..1001
    --------------------------------------------------------------------------
    INSERT INTO oj_skew
    SELECT level,
           CASE
             WHEN level <= 99000 THEN 1
             ELSE MOD(level,1000)+2
           END,
           RPAD('SKEW',100,'S')
    FROM dual
    CONNECT BY level <= 100000;

    COMMIT;
END;
/

--------------------------------------------------------------------------------
-- 3. INDEXES
--------------------------------------------------------------------------------

CREATE INDEX oj_emp_dept_i
    ON oj_emp(dept_id);

CREATE INDEX oj_emp_status_i
    ON oj_emp(status);

CREATE INDEX oj_orders_customer_i
    ON oj_orders(customer_id);

CREATE INDEX oj_orders_date_i
    ON oj_orders(order_date);

CREATE INDEX oj_orders_status_i
    ON oj_orders(status);

CREATE INDEX oj_order_items_product_i
    ON oj_order_items(product_id);

CREATE INDEX oj_sales_customer_i
    ON oj_sales(customer_id);

CREATE INDEX oj_sales_date_i
    ON oj_sales(sale_date);

CREATE INDEX oj_sales_region_i
    ON oj_sales(region);

CREATE INDEX oj_big_group_i
    ON oj_big(group_id);

CREATE INDEX oj_small_group_i
    ON oj_small(group_id);

CREATE INDEX oj_skew_col_i
    ON oj_skew(skew_col);

--------------------------------------------------------------------------------
-- 4. INITIAL GOOD STATISTICS
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname          => USER,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        cascade          => TRUE,
        no_invalidate    => FALSE
    );
END;
/

--------------------------------------------------------------------------------
-- Helper procedure
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE trace_on(
    p_test_id VARCHAR2
)
IS
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('====================================================');
    DBMS_OUTPUT.PUT_LINE('STARTING TEST: ' || p_test_id);
    DBMS_OUTPUT.PUT_LINE('====================================================');

    /*
       10053:
          Optimizer trace.

       10046 level 12:
          SQL trace + waits + binds.
    */

    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10053 trace name context forever, level 1''';

    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10046 trace name context forever, level 12''';
END;
/

CREATE OR REPLACE PROCEDURE trace_off
IS
BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10053 trace name context off''';

    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10046 trace name context off''';

    DBMS_OUTPUT.PUT_LINE('TRACE OFF');
END;
/

--------------------------------------------------------------------------------
-- 5. TEST 01 - NESTED LOOP JOIN
--
-- Goal:
--   Small driving row source + indexed lookup into larger table.
--
-- Look in 10053 for:
--   - Join order
--   - NL costing
--   - Index access cost
--   - Cardinality
--   - Join cardinality
--------------------------------------------------------------------------------

EXEC trace_on('T01_NESTED_LOOP');

SELECT /* T01_NESTED_LOOP */
       /*+ LEADING(c o) USE_NL(o) INDEX(o oj_orders_customer_i) */
       c.customer_id,
       c.customer_name,
       o.order_id,
       o.amount
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id <= 10;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE +PEEKED_BINDS'
    )
);

--------------------------------------------------------------------------------
-- 6. TEST 02 - HASH JOIN
--------------------------------------------------------------------------------

EXEC trace_on('T02_HASH_JOIN');

SELECT /* T02_HASH_JOIN */
       /*+ USE_HASH(o c) */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON c.customer_id = o.customer_id
WHERE o.order_date >= DATE '2025-01-01';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 7. TEST 03 - SORT MERGE JOIN
--
-- USE_MERGE makes this deterministic for the lab.
--
-- 10053 lets you examine:
--   - Sort cost
--   - Merge join costing
--   - Join order
--------------------------------------------------------------------------------

EXEC trace_on('T03_SORT_MERGE');

SELECT /* T03_SORT_MERGE */
       /*+ USE_MERGE(s c) */
       COUNT(*)
FROM oj_sales s
JOIN oj_customer c
  ON c.customer_id = s.customer_id
WHERE s.sale_date >= DATE '2025-01-01';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 8. TEST 04 - CARTESIAN JOIN
--
-- Deliberately no join predicate.
--
-- 10053:
--   Search for Cartesian / join order / cost.
--------------------------------------------------------------------------------

EXEC trace_on('T04_CARTESIAN');

SELECT /* T04_CARTESIAN */
       /*+ LEADING(c p) */
       COUNT(*)
FROM (
    SELECT *
    FROM oj_customer
    WHERE customer_id <= 100
) c,
(
    SELECT *
    FROM oj_product
    WHERE product_id <= 20
) p;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 9. TEST 05 - VIEW MERGING
--
-- Inline view should normally be mergeable.
--
-- Compare with T06 where NO_MERGE prevents merging.
--------------------------------------------------------------------------------

EXEC trace_on('T05_VIEW_MERGING');

SELECT /* T05_VIEW_MERGING */
       v.customer_id,
       v.cnt
FROM (
    SELECT customer_id,
           COUNT(*) cnt
    FROM oj_orders
    GROUP BY customer_id
) v
WHERE v.customer_id <= 100;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 10. TEST 06 - VIEW MERGING DISABLED
--------------------------------------------------------------------------------

EXEC trace_on('T06_NO_VIEW_MERGING');

SELECT /* T06_NO_VIEW_MERGING */
       /*+ NO_MERGE(v) */
       v.customer_id,
       v.cnt
FROM (
    SELECT customer_id,
           COUNT(*) cnt
    FROM oj_orders
    GROUP BY customer_id
) v
WHERE v.customer_id <= 100;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 11. TEST 07 - SUBQUERY UNNESTING
--------------------------------------------------------------------------------

EXEC trace_on('T07_SUBQUERY_UNNESTING');

SELECT /* T07_SUBQUERY_UNNESTING */
       COUNT(*)
FROM oj_customer c
WHERE EXISTS (
    SELECT 1
    FROM oj_orders o
    WHERE o.customer_id = c.customer_id
      AND o.amount > 9000
);

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 12. TEST 08 - NO UNNEST
--------------------------------------------------------------------------------

EXEC trace_on('T08_NO_UNNEST');

SELECT /* T08_NO_UNNEST */
       /*+ NO_UNNEST */
       COUNT(*)
FROM oj_customer c
WHERE EXISTS (
    SELECT 1
    FROM oj_orders o
    WHERE o.customer_id = c.customer_id
      AND o.amount > 9000
);

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 13. TEST 09 - PREDICATE PUSHING
--------------------------------------------------------------------------------

EXEC trace_on('T09_PREDICATE_PUSHING');

SELECT /* T09_PREDICATE_PUSHING */
       v.customer_id,
       v.total_amount
FROM (
    SELECT o.customer_id,
           SUM(o.amount) total_amount
    FROM oj_orders o
    GROUP BY o.customer_id
) v
WHERE v.customer_id BETWEEN 100 AND 200;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 14. TEST 10 - OR EXPANSION
--------------------------------------------------------------------------------

EXEC trace_on('T10_OR_EXPANSION');

SELECT /* T10_OR_EXPANSION */
       COUNT(*)
FROM oj_orders
WHERE customer_id = 100
   OR customer_id = 200
   OR customer_id = 300;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 15. TEST 11 - JOIN ELIMINATION
--
-- The query does not actually need columns from CUSTOMER.
--------------------------------------------------------------------------------

EXEC trace_on('T11_JOIN_ELIMINATION');

SELECT /* T11_JOIN_ELIMINATION */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON c.customer_id = o.customer_id
WHERE o.amount > 9000;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 16. TEST 12 - PREDICATE TRANSTIVITY
--------------------------------------------------------------------------------

EXEC trace_on('T12_PREDICATE_TRANSTIVITY');

SELECT /* T12_PREDICATE_TRANSTIVITY */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON o.customer_id = c.customer_id
WHERE c.customer_id = 12345;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 17. TEST 13 - MISSING INDEX
--
-- Drop the useful index first.
--------------------------------------------------------------------------------

DROP INDEX oj_orders_customer_i;

EXEC trace_on('T13_MISSING_INDEX');

SELECT /* T13_MISSING_INDEX */
       /*+ LEADING(c o) */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 1 AND 10;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- Restore index
--------------------------------------------------------------------------------

CREATE INDEX oj_orders_customer_i
    ON oj_orders(customer_id);

--------------------------------------------------------------------------------
-- 18. TEST 14 - MISSING STATISTICS
--
-- Create a new table with no statistics.
--------------------------------------------------------------------------------

CREATE TABLE oj_no_stats AS
SELECT *
FROM oj_orders
WHERE 1=0;

INSERT INTO oj_no_stats
SELECT *
FROM oj_orders
WHERE order_id <= 100000;

COMMIT;

-- Intentionally DO NOT gather stats.

EXEC trace_on('T14_MISSING_STATISTICS');

SELECT /* T14_MISSING_STATISTICS */
       COUNT(*)
FROM oj_no_stats
WHERE customer_id = 100;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 19. TEST 15 - STALE / BAD STATISTICS
--
-- First gather correct statistics.
-- Then insert a large amount of data without gathering statistics.
--------------------------------------------------------------------------------

CREATE TABLE oj_stale AS
SELECT *
FROM oj_skew;

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname => USER,
        tabname => 'OJ_STALE',
        cascade => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO'
    );
END;
/

INSERT INTO oj_stale
SELECT id + 100000,
       skew_col,
       payload
FROM oj_skew
CROSS JOIN (
    SELECT 1 x FROM dual CONNECT BY level <= 5
);

COMMIT;

EXEC trace_on('T15_STALE_STATISTICS');

SELECT /* T15_STALE_STATISTICS */
       COUNT(*)
FROM oj_stale
WHERE skew_col = 1;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 20. TEST 16 - BAD STATISTICS / WRONG CARDINALITY
--
-- Deliberately manipulate statistics.
--
-- We set NUM_ROWS very differently from reality.
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.SET_TABLE_STATS(
        ownname => USER,
        tabname => 'OJ_BIG',
        numrows => 100
    );

    DBMS_STATS.SET_TABLE_STATS(
        ownname => USER,
        tabname => 'OJ_SMALL',
        numrows => 100000000
    );
END;
/

EXEC trace_on('T16_BAD_TABLE_STATS');

SELECT /* T16_BAD_TABLE_STATS */
       /*+ USE_HASH(b s) */
       COUNT(*)
FROM oj_big b
JOIN oj_small s
  ON s.group_id = b.group_id;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 21. TEST 17 - CARDINALITY MIS-ESTIMATE FROM SKEW
--
-- We deliberately remove useful histogram information.
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname     => USER,
        tabname     => 'OJ_SKEW',
        cascade     => TRUE,
        method_opt  => 'FOR ALL COLUMNS SIZE 1'
    );
END;
/

EXEC trace_on('T17_CARDINALITY_SKEW');

SELECT /* T17_CARDINALITY_SKEW */
       COUNT(*)
FROM oj_skew
WHERE skew_col = 1;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 22. TEST 18 - GOOD HISTOGRAM
--
-- Compare against T17.
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname     => USER,
        tabname     => 'OJ_SKEW',
        cascade     => TRUE,
        method_opt  => 'FOR ALL COLUMNS SIZE 254'
    );
END;
/

EXEC trace_on('T18_GOOD_HISTOGRAM');

SELECT /* T18_GOOD_HISTOGRAM */
       COUNT(*)
FROM oj_skew
WHERE skew_col = 1;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 23. TEST 19 - BAD CLUSTERING FACTOR
--
-- Build a table whose physical order is very different from index order.
--
-- We create a copy ordered by another column and then index COL_A.
--------------------------------------------------------------------------------

CREATE TABLE oj_clustering AS
SELECT level id,
       MOD(level,1000) col_a,
       TRUNC(level/1000) col_b,
       RPAD('CLUSTER',200,'C') payload
FROM dual
CONNECT BY level <= 500000;

CREATE INDEX oj_clustering_i
    ON oj_clustering(col_a);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname    => USER,
        tabname    => 'OJ_CLUSTERING',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO'
    );
END;
/

EXEC trace_on('T19_CLUSTERING_FACTOR');

SELECT /* T19_CLUSTERING_FACTOR */
       COUNT(*)
FROM oj_clustering
WHERE col_a BETWEEN 1 AND 20;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- Show clustering factor
--------------------------------------------------------------------------------

COLUMN INDEX_NAME FORMAT A30
COLUMN TABLE_NAME FORMAT A25

SELECT index_name,
       table_name,
       num_rows,
       distinct_keys,
       clustering_factor
FROM user_indexes
WHERE index_name = 'OJ_CLUSTERING_I';

--------------------------------------------------------------------------------
-- 24. TEST 20 - SPARSE / LOW COVERAGE INDEX
--
-- Only a small percentage of rows match FLAG='Y'.
--------------------------------------------------------------------------------

CREATE INDEX oj_sales_flag_i
    ON oj_sales(flag);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname    => USER,
        tabname    => 'OJ_SALES',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO'
    );
END;
/

EXEC trace_on('T20_SPARSE_SELECTIVE_INDEX');

SELECT /* T20_SPARSE_SELECTIVE_INDEX */
       COUNT(*)
FROM oj_sales
WHERE flag = 'Y';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 25. TEST 21 - NON-SELECTIVE INDEX
--
-- Same index but predicate matches almost all rows.
--------------------------------------------------------------------------------

EXEC trace_on('T21_NONSELECTIVE_INDEX');

SELECT /* T21_NONSELECTIVE_INDEX */
       COUNT(*)
FROM oj_sales
WHERE flag = 'N';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 26. TEST 22 - INDEX VS FULL TABLE SCAN
--------------------------------------------------------------------------------

EXEC trace_on('T22_INDEX_VS_FTS');

SELECT /* T22_INDEX_VS_FTS */
       SUM(amount)
FROM oj_sales
WHERE customer_id = 12345;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 27. TEST 23 - FUNCTION ON COLUMN / ACCESS PATH PROBLEM
--------------------------------------------------------------------------------

EXEC trace_on('T23_FUNCTION_COLUMN');

SELECT /* T23_FUNCTION_COLUMN */
       COUNT(*)
FROM oj_orders
WHERE TRUNC(order_date) = DATE '2025-01-01';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 28. TEST 24 - SARGABLE VERSION
--
-- Compare with T23.
--------------------------------------------------------------------------------

EXEC trace_on('T24_SARGABLE_DATE');

SELECT /* T24_SARGABLE_DATE */
       COUNT(*)
FROM oj_orders
WHERE order_date >= DATE '2025-01-01'
  AND order_date <  DATE '2025-01-02';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 29. TEST 25 - ADAPTIVE / STATISTICS FEEDBACK OBSERVATION
--
-- This is intentionally not forced.
--
-- Depending on optimizer settings / compatibility / execution history,
-- Oracle may use statistics feedback or other adaptive behavior.
--
-- Execute multiple times.
--------------------------------------------------------------------------------

ALTER SESSION SET optimizer_adaptive_plans = TRUE;

ALTER SESSION SET optimizer_adaptive_statistics = TRUE;

EXEC trace_on('T25_ADAPTIVE_FEATURES');

SELECT /* T25_ADAPTIVE_FEATURES */
       c.region,
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE o.amount > 9900
GROUP BY c.region;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE +REPORT'
    )
);

--------------------------------------------------------------------------------
-- Execute again so that feedback/adaptive behavior can be observed where
-- applicable.
--------------------------------------------------------------------------------

EXEC trace_on('T25_ADAPTIVE_FEATURES_SECOND_EXEC');

SELECT /* T25_ADAPTIVE_FEATURES_SECOND_EXEC */
       c.region,
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE o.amount > 9900
GROUP BY c.region;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE +REPORT'
    )
);

--------------------------------------------------------------------------------
-- 30. TEST 26 - JOIN ORDER
--------------------------------------------------------------------------------

EXEC trace_on('T26_JOIN_ORDER');

SELECT /* T26_JOIN_ORDER */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
JOIN oj_order_items oi
  ON oi.order_id = o.order_id
JOIN oj_product p
  ON p.product_id = oi.product_id
WHERE c.region = 'NORTH'
  AND p.category = 'ELECTRONICS';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 31. TEST 27 - FORCED JOIN ORDER
--------------------------------------------------------------------------------

EXEC trace_on('T27_FORCED_JOIN_ORDER');

SELECT /* T27_FORCED_JOIN_ORDER */
       /*+ ORDERED */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
JOIN oj_order_items oi
  ON oi.order_id = o.order_id
JOIN oj_product p
  ON p.product_id = oi.product_id
WHERE c.region = 'NORTH'
  AND p.category = 'ELECTRONICS';

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 32. TEST 28 - NESTED LOOP VS HASH JOIN
--
-- Same logical query.
-- Explicitly compare both strategies.
--------------------------------------------------------------------------------

EXEC trace_on('T28A_FORCE_NL');

SELECT /* T28A_FORCE_NL */
       /*+ USE_NL(o) */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 1 AND 1000;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

EXEC trace_on('T28B_FORCE_HASH');

SELECT /* T28B_FORCE_HASH */
       /*+ USE_HASH(o) */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 1 AND 1000;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 33. TEST 29 - SQL TRANSFORMATION COMBINATION
--
-- View + EXISTS + predicates.
--------------------------------------------------------------------------------

EXEC trace_on('T29_COMBINED_TRANSFORMATIONS');

SELECT /* T29_COMBINED_TRANSFORMATIONS */
       v.region,
       COUNT(*)
FROM (
    SELECT c.customer_id,
           c.region
    FROM oj_customer c
    WHERE c.status = 'ACTIVE'
      AND EXISTS (
          SELECT 1
          FROM oj_orders o
          WHERE o.customer_id = c.customer_id
            AND o.amount > 9000
      )
) v
JOIN oj_orders o
  ON o.customer_id = v.customer_id
WHERE o.order_date >= DATE '2025-01-01'
GROUP BY v.region;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 34. TEST 30 - CARDINALITY + JOIN METHOD
--
-- Deliberately bad statistics on one side.
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.SET_TABLE_STATS(
        ownname => USER,
        tabname => 'OJ_SMALL',
        numrows => 1
    );
END;
/

EXEC trace_on('T30_BAD_CARDINALITY_JOIN');

SELECT /* T30_BAD_CARDINALITY_JOIN */
       COUNT(*)
FROM oj_big b
JOIN oj_small s
  ON s.group_id = b.group_id
WHERE s.group_id BETWEEN 1 AND 100;

EXEC trace_off;

SELECT *
FROM TABLE(
    DBMS_XPLAN.DISPLAY_CURSOR(
        NULL,NULL,
        'ALLSTATS LAST +OUTLINE +NOTE'
    )
);

--------------------------------------------------------------------------------
-- 35. RESTORE GOOD STATISTICS
--------------------------------------------------------------------------------

BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname          => USER,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        cascade          => TRUE,
        no_invalidate    => FALSE
    );
END;
/

--------------------------------------------------------------------------------
-- 36. DISPLAY IMPORTANT OPTIMIZER SETTINGS
--------------------------------------------------------------------------------

COLUMN NAME FORMAT A45
COLUMN VALUE FORMAT A60

SELECT name, value
FROM v$parameter
WHERE name IN (
    'optimizer_features_enable',
    'optimizer_mode',
    'optimizer_dynamic_sampling',
    'optimizer_adaptive_plans',
    'optimizer_adaptive_statistics',
    'statistics_level',
    'cursor_sharing'
)
ORDER BY name;

--------------------------------------------------------------------------------
-- 37. TRACE FILE LOCATION
--------------------------------------------------------------------------------

SELECT name, value
FROM v$diag_info
WHERE name IN (
    'Diag Trace',
    'Default Trace File',
    'Default Trace Directory'
);

--------------------------------------------------------------------------------
-- 38. CURRENT SESSION INFORMATION
--------------------------------------------------------------------------------

SELECT sid,
       serial#,
       sql_id,
       prev_sql_id,
       module,
       action
FROM v$session
WHERE sid = SYS_CONTEXT('USERENV','SID');

--------------------------------------------------------------------------------
-- END
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT OPTIMIZER TRACE LAB COMPLETE
PROMPT ============================================================
PROMPT
PROMPT Important trace IDs:
PROMPT
PROMPT T01  Nested Loop
PROMPT T02  Hash Join
PROMPT T03  Sort Merge Join
PROMPT T04  Cartesian Join
PROMPT T05  View Merging
PROMPT T06  No View Merging
PROMPT T07  Subquery Unnesting
PROMPT T08  No Unnest
PROMPT T09  Predicate Pushing
PROMPT T10  OR Expansion
PROMPT T11  Join Elimination
PROMPT T12  Predicate Transitivity
PROMPT T13  Missing Index
PROMPT T14  Missing Statistics
PROMPT T15  Stale Statistics
PROMPT T16  Bad Table Statistics
PROMPT T17  Cardinality Misestimate / No Histogram
PROMPT T18  Histogram
PROMPT T19  Bad Clustering Factor
PROMPT T20  Selective/Sparse Index
PROMPT T21  Non-selective Index
PROMPT T22  Index vs Full Table Scan
PROMPT T23  Function on Column
PROMPT T24  SARGable Predicate
PROMPT T25  Adaptive Features
PROMPT T26  Join Order
PROMPT T27  Forced Join Order
PROMPT T28  NL vs Hash
PROMPT T29  Combined Transformations
PROMPT T30  Bad Cardinality + Join
PROMPT
PROMPT Use V$DIAG_INFO to locate 10046/10053 trace files.
PROMPT ============================================================
