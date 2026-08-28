```sql
--------------------------------------------------------------------------------
-- ============================================================================
-- ORACLE DATABASE 23ai
-- OPTIMIZER / 10053 / 10046 LEVEL 12 TRAINING LAB
-- ============================================================================
--
-- VERSION: 2.0
--
-- PURPOSE
-- -------
-- Demonstrate and trace:
--
-- JOIN METHODS
--   T01  Nested Loop
--   T02  Hash Join
--   T03  Sort Merge Join
--   T04  Cartesian Join
--
-- QUERY TRANSFORMATIONS
--   T05  View Merging
--   T06  NO_MERGE
--   T07  Subquery Unnesting
--   T08  NO_UNNEST
--   T09  Predicate Pushing
--   T10  OR Expansion
--   T11  Join Elimination
--   T12  Predicate Transitivity
--
-- ACCESS PATH / STATISTICS
--   T13  Missing Index
--   T14  Missing Statistics
--   T15  Stale Statistics
--   T16  Bad Table Statistics
--   T17  Cardinality Misestimate / No Histogram
--   T18  Histogram
--   T19  Clustering Factor
--   T20  Selective Index
--   T21  Non-selective Index
--   T22  Index vs Full Scan
--   T23  Function on Column
--   T24  SARGable Predicate
--
-- ADAPTIVE / JOIN ORDER
--   T25  Adaptive Plan
--   T26  Join Order
--   T27  Forced Join Order
--   T28  NL vs HASH
--   T29  Combined Transformations
--   T30  Bad Cardinality + Join
--
-- TRACING
-- --------
-- 10053 = Optimizer decision / costing / transformation trace
-- 10046 = SQL trace, waits and binds
--
-- IMPORTANT
-- ---------
-- 1. Every SQL statement has a unique LAB tag.
-- 2. SQL_ID is retrieved from V$SQL using the tag.
-- 3. DBMS_XPLAN.DISPLAY_CURSOR is called with exact SQL_ID + child number.
-- 4. We NEVER use DISPLAY_CURSOR(NULL,NULL).
-- 5. Do not use multiline SQL*Plus EXEC syntax.
-- 6. Each show_test_plan call is one line.
--
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 250
SET PAGESIZE 100
SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET TAB OFF
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING ON

ALTER SESSION SET statistics_level = ALL;
ALTER SESSION SET cursor_sharing = EXACT;

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 0 - SESSION INFORMATION
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT SESSION INFORMATION
PROMPT ============================================================

SELECT
    SYS_CONTEXT('USERENV','DB_NAME')       AS db_name,
    SYS_CONTEXT('USERENV','CURRENT_USER')  AS username,
    SYS_CONTEXT('USERENV','SID')           AS sid,
    SYS_CONTEXT('USERENV','INSTANCE_NAME') AS instance_name
FROM dual;

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 1 - DISABLE TRACE IF LEFT ON FROM PREVIOUS RUN
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10053 trace name context off''';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10046 trace name context off''';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 2 - CLEAN OLD OBJECTS
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT DROPPING OLD LAB OBJECTS
PROMPT ============================================================

BEGIN

    FOR r IN
    (
        SELECT object_name,
               object_type
        FROM user_objects
        WHERE object_name IN
        (
            'OJ_DEPT',
            'OJ_EMP',
            'OJ_CUSTOMER',
            'OJ_ORDERS',
            'OJ_ORDER_ITEMS',
            'OJ_PRODUCT',
            'OJ_SALES',
            'OJ_BIG',
            'OJ_SMALL',
            'OJ_SKEW',
            'OJ_NO_STATS',
            'OJ_STALE',
            'OJ_CLUSTERING',
            'OJ_TRACE_RESULTS'
        )
        ORDER BY
            CASE object_type
                WHEN 'TABLE' THEN 1
                ELSE 2
            END
    )
    LOOP

        BEGIN

            IF r.object_type = 'TABLE' THEN

                EXECUTE IMMEDIATE
                    'DROP TABLE ' ||
                    r.object_name ||
                    ' CASCADE CONSTRAINTS PURGE';

            END IF;

        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

    END LOOP;

END;
/

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 3 - CREATE TABLES
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT CREATING TABLES
PROMPT ============================================================

CREATE TABLE oj_dept
(
    dept_id       NUMBER PRIMARY KEY,
    dept_name     VARCHAR2(100),
    region        VARCHAR2(30)
);

CREATE TABLE oj_emp
(
    emp_id        NUMBER PRIMARY KEY,
    dept_id       NUMBER,
    emp_name      VARCHAR2(100),
    job           VARCHAR2(50),
    salary        NUMBER,
    hire_date     DATE,
    status        VARCHAR2(20)
);

CREATE TABLE oj_customer
(
    customer_id   NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100),
    region        VARCHAR2(30),
    customer_type VARCHAR2(20),
    status        VARCHAR2(20)
);

CREATE TABLE oj_orders
(
    order_id      NUMBER PRIMARY KEY,
    customer_id   NUMBER,
    order_date    DATE,
    status        VARCHAR2(20),
    amount        NUMBER
);

CREATE TABLE oj_order_items
(
    order_id      NUMBER,
    line_id       NUMBER,
    product_id    NUMBER,
    quantity      NUMBER,
    price         NUMBER,
    CONSTRAINT oj_order_items_pk
        PRIMARY KEY (order_id,line_id)
);

CREATE TABLE oj_product
(
    product_id    NUMBER PRIMARY KEY,
    product_name  VARCHAR2(100),
    category      VARCHAR2(30),
    price         NUMBER
);

CREATE TABLE oj_sales
(
    sale_id       NUMBER PRIMARY KEY,
    customer_id   NUMBER,
    sale_date     DATE,
    region        VARCHAR2(30),
    product_id    NUMBER,
    amount        NUMBER,
    flag          VARCHAR2(1)
);

CREATE TABLE oj_big
(
    id            NUMBER PRIMARY KEY,
    group_id      NUMBER,
    payload       VARCHAR2(100)
);

CREATE TABLE oj_small
(
    id            NUMBER PRIMARY KEY,
    group_id      NUMBER,
    payload       VARCHAR2(100)
);

CREATE TABLE oj_skew
(
    id            NUMBER PRIMARY KEY,
    skew_col      NUMBER,
    payload       VARCHAR2(100)
);

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 4 - GENERATE DATA
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT GENERATING DATA
PROMPT ============================================================

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
       CASE
           WHEN MOD(level,10) IN (0,1)
           THEN 'VIP'
           ELSE 'STANDARD'
       END,
       CASE
           WHEN MOD(level,25) = 0
           THEN 'INACTIVE'
           ELSE 'ACTIVE'
       END
FROM dual
CONNECT BY level <= 50000;


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


INSERT INTO oj_order_items
SELECT o.order_id,
       x.line_id,
       MOD(o.order_id * 17 + x.line_id * 31,1000) + 1,
       MOD(o.order_id + x.line_id,10) + 1,
       10 + MOD(o.order_id * 13 + x.line_id * 7,1000)
FROM oj_orders o
CROSS JOIN
(
    SELECT level line_id
    FROM dual
    CONNECT BY level <= 3
) x;


INSERT INTO oj_sales
SELECT level,
       MOD(level * 13,50000) + 1,
       DATE '2024-01-01' + MOD(level,700),
       CASE MOD(level,5)
           WHEN 0 THEN 'NORTH'
           WHEN 1 THEN 'SOUTH'
           WHEN 2 THEN 'EAST'
           WHEN 3 THEN 'WEST'
           ELSE 'CENTRAL'
       END,
       MOD(level * 17,1000) + 1,
       1 + MOD(level * 7919,5000),
       CASE
           WHEN MOD(level,100) = 0 THEN 'Y'
           ELSE 'N'
       END
FROM dual
CONNECT BY level <= 1000000;


INSERT INTO oj_big
SELECT level,
       MOD(level,10000),
       RPAD('BIG',100,'X')
FROM dual
CONNECT BY level <= 1000000;


INSERT INTO oj_small
SELECT level,
       MOD(level,10000),
       RPAD('SMALL',100,'Y')
FROM dual
CONNECT BY level <= 10000;


INSERT INTO oj_skew
SELECT level,
       CASE
           WHEN level <= 99000 THEN 1
           ELSE MOD(level,1000) + 2
       END,
       RPAD('SKEW',100,'S')
FROM dual
CONNECT BY level <= 100000;

COMMIT;

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 5 - INDEXES
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT CREATING INDEXES
PROMPT ============================================================

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
-- ============================================================================
-- SECTION 6 - FOREIGN KEY FOR JOIN ELIMINATION EXPERIMENT
-- ============================================================================
--------------------------------------------------------------------------------

ALTER TABLE oj_orders
ADD CONSTRAINT oj_orders_customer_fk
FOREIGN KEY (customer_id)
REFERENCES oj_customer(customer_id);

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 7 - GATHER GOOD INITIAL STATISTICS
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT GATHERING INITIAL STATISTICS
PROMPT ============================================================

BEGIN

    DBMS_STATS.GATHER_SCHEMA_STATS
    (
        ownname          => USER,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
        cascade          => TRUE,
        no_invalidate    => FALSE
    );

END;
/

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 8 - RESULT TABLE
-- ============================================================================
--------------------------------------------------------------------------------

CREATE TABLE oj_trace_results
(
    test_id           VARCHAR2(100),
    test_description  VARCHAR2(500),
    run_time          TIMESTAMP,
    sql_id            VARCHAR2(13),
    child_number      NUMBER,
    plan_hash_value   NUMBER,
    executions        NUMBER,
    elapsed_time_us   NUMBER,
    cpu_time_us       NUMBER,
    buffer_gets       NUMBER,
    disk_reads        NUMBER,
    rows_processed    NUMBER,
    trace_file        VARCHAR2(1000)
);

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 9 - TRACE ON
-- ============================================================================
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE trace_on
(
    p_test_id IN VARCHAR2
)
IS
BEGIN

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(
        '============================================================'
    );

    DBMS_OUTPUT.PUT_LINE(
        'TRACE ON: ' || p_test_id
    );

    DBMS_OUTPUT.PUT_LINE(
        '============================================================'
    );

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

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 10 - TRACE OFF
-- ============================================================================
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE trace_off
IS
BEGIN

    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10053 trace name context off''';

    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10046 trace name context off''';

END;
/

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 11 - SHOW EXACT TEST PLAN
--
-- This is the critical fix.
--
-- NEVER:
--
--   DBMS_XPLAN.DISPLAY_CURSOR(NULL,NULL,...)
--
-- Instead:
--
--   find SQL_ID from V$SQL
--   find CHILD_NUMBER
--   pass both explicitly.
-- ============================================================================
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE show_test_plan
(
    p_test_id     IN VARCHAR2,
    p_description IN VARCHAR2 DEFAULT NULL
)
IS

    l_sql_id          VARCHAR2(13);
    l_child_number    NUMBER;
    l_plan_hash       NUMBER;
    l_executions      NUMBER;
    l_elapsed         NUMBER;
    l_cpu_time        NUMBER;
    l_buffer_gets     NUMBER;
    l_disk_reads      NUMBER;
    l_rows_processed  NUMBER;
    l_trace_file      VARCHAR2(1000);

BEGIN

    /*
       Find most recently active cursor containing our LAB tag.

       DBMS_OUTPUT.GET_LINES cannot match the tag,
       so it cannot be accidentally selected.
    */

    BEGIN

        SELECT sql_id,
               child_number,
               plan_hash_value,
               executions,
               elapsed_time,
               cpu_time,
               buffer_gets,
               disk_reads,
               rows_processed
        INTO   l_sql_id,
               l_child_number,
               l_plan_hash,
               l_executions,
               l_elapsed,
               l_cpu_time,
               l_buffer_gets,
               l_disk_reads,
               l_rows_processed
        FROM
        (
            SELECT sql_id,
                   child_number,
                   plan_hash_value,
                   executions,
                   elapsed_time,
                   cpu_time,
                   buffer_gets,
                   disk_reads,
                   rows_processed,
                   last_active_time
            FROM v$sql
            WHERE UPPER(sql_text) LIKE '%' ||
                  UPPER(p_test_id) ||
                  '%'
            AND sql_text NOT LIKE '%OJ_TRACE_RESULTS%'
            ORDER BY last_active_time DESC
        )
        WHERE ROWNUM = 1;

    EXCEPTION

        WHEN NO_DATA_FOUND THEN

            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE(
                'ERROR: SQL_ID not found for test: ' ||
                p_test_id
            );

            DBMS_OUTPUT.PUT_LINE(
                'Search V$SQL manually using the test tag.'
            );

            RETURN;

    END;


    /*
       Trace file.
    */

    BEGIN

        SELECT value
        INTO l_trace_file
        FROM v$diag_info
        WHERE name = 'Default Trace File';

    EXCEPTION

        WHEN NO_DATA_FOUND THEN
            l_trace_file := NULL;

    END;


    /*
       Print metadata.
    */

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(
        '------------------------------------------------------------'
    );

    DBMS_OUTPUT.PUT_LINE(
        'TEST ID       : ' || p_test_id
    );

    DBMS_OUTPUT.PUT_LINE(
        'DESCRIPTION   : ' || p_description
    );

    DBMS_OUTPUT.PUT_LINE(
        'SQL_ID        : ' || l_sql_id
    );

    DBMS_OUTPUT.PUT_LINE(
        'CHILD NUMBER  : ' || l_child_number
    );

    DBMS_OUTPUT.PUT_LINE(
        'PLAN HASH      : ' || l_plan_hash
    );

    DBMS_OUTPUT.PUT_LINE(
        'EXECUTIONS    : ' || l_executions
    );

    DBMS_OUTPUT.PUT_LINE(
        'ELAPSED (us)  : ' || l_elapsed
    );

    DBMS_OUTPUT.PUT_LINE(
        'CPU (us)      : ' || l_cpu_time
    );

    DBMS_OUTPUT.PUT_LINE(
        'BUFFER GETS   : ' || l_buffer_gets
    );

    DBMS_OUTPUT.PUT_LINE(
        'DISK READS    : ' || l_disk_reads
    );

    DBMS_OUTPUT.PUT_LINE(
        'ROWS          : ' || l_rows_processed
    );

    DBMS_OUTPUT.PUT_LINE(
        'TRACE FILE    : ' || l_trace_file
    );

    DBMS_OUTPUT.PUT_LINE(
        '------------------------------------------------------------'
    );


    /*
       Store result.
    */

    INSERT INTO oj_trace_results
    (
        test_id,
        test_description,
        run_time,
        sql_id,
        child_number,
        plan_hash_value,
        executions,
        elapsed_time_us,
        cpu_time_us,
        buffer_gets,
        disk_reads,
        rows_processed,
        trace_file
    )
    VALUES
    (
        p_test_id,
        p_description,
        SYSTIMESTAMP,
        l_sql_id,
        l_child_number,
        l_plan_hash,
        l_executions,
        l_elapsed,
        l_cpu_time,
        l_buffer_gets,
        l_disk_reads,
        l_rows_processed,
        l_trace_file
    );

    COMMIT;


    /*
       Display exact cursor.
    */

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(
        'EXECUTION PLAN'
    );

    DBMS_OUTPUT.PUT_LINE(
        '--------------'
    );

    FOR r IN
    (
        SELECT plan_table_output
        FROM TABLE
        (
            DBMS_XPLAN.DISPLAY_CURSOR
            (
                l_sql_id,
                l_child_number,
                'ALLSTATS LAST +OUTLINE +NOTE +PEEKED_BINDS +REPORT'
            )
        )
    )
    LOOP

        DBMS_OUTPUT.PUT_LINE(
            r.plan_table_output
        );

    END LOOP;

END;
/

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 12 - TRACE FILE INFORMATION
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT TRACE DIRECTORY
PROMPT ============================================================

SELECT name,
       value
FROM v$diag_info
WHERE name IN
(
    'Diag Trace',
    'Default Trace File',
    'Default Trace Directory'
);

--------------------------------------------------------------------------------
-- ============================================================================
-- T01 - NESTED LOOP
-- ============================================================================
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

EXEC show_test_plan('T01_NESTED_LOOP','Nested Loop Join');

--------------------------------------------------------------------------------
-- T02 - HASH JOIN
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T02_HASH_JOIN');

SELECT /* T02_HASH_JOIN */
       /*+ USE_HASH(o) */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON c.customer_id = o.customer_id
WHERE o.order_date >= DATE '2025-01-01';

EXEC trace_off;

EXEC show_test_plan('T02_HASH_JOIN','Hash Join');

--------------------------------------------------------------------------------
-- T03 - SORT MERGE JOIN
-- ============================================================================
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

EXEC show_test_plan('T03_SORT_MERGE','Sort Merge Join');

--------------------------------------------------------------------------------
-- T04 - CARTESIAN JOIN
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T04_CARTESIAN');

SELECT /* T04_CARTESIAN */
       /*+ USE_NL(p) */
       COUNT(*)
FROM
(
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

EXEC show_test_plan('T04_CARTESIAN','Cartesian Join');

--------------------------------------------------------------------------------
-- T05 - VIEW MERGING
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T05_VIEW_MERGING');

SELECT /* T05_VIEW_MERGING */
       v.customer_id,
       v.cnt
FROM
(
    SELECT customer_id,
           COUNT(*) cnt
    FROM oj_orders
    GROUP BY customer_id
) v
WHERE v.customer_id <= 100;

EXEC trace_off;

EXEC show_test_plan('T05_VIEW_MERGING','View Merging');

--------------------------------------------------------------------------------
-- T06 - NO VIEW MERGING
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T06_NO_MERGE');

SELECT /* T06_NO_MERGE */
       /*+ NO_MERGE(v) */
       v.customer_id,
       v.cnt
FROM
(
    SELECT customer_id,
           COUNT(*) cnt
    FROM oj_orders
    GROUP BY customer_id
) v
WHERE v.customer_id <= 100;

EXEC trace_off;

EXEC show_test_plan('T06_NO_MERGE','View Merging Disabled');

--------------------------------------------------------------------------------
-- T07 - SUBQUERY UNNESTING
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T07_SUBQUERY_UNNESTING');

SELECT /* T07_SUBQUERY_UNNESTING */
       COUNT(*)
FROM oj_customer c
WHERE EXISTS
(
    SELECT 1
    FROM oj_orders o
    WHERE o.customer_id = c.customer_id
      AND o.amount > 9000
);

EXEC trace_off;

EXEC show_test_plan('T07_SUBQUERY_UNNESTING','Subquery Unnesting');

--------------------------------------------------------------------------------
-- T08 - NO UNNEST
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T08_NO_UNNEST');

SELECT /* T08_NO_UNNEST */
       /*+ NO_UNNEST */
       COUNT(*)
FROM oj_customer c
WHERE EXISTS
(
    SELECT 1
    FROM oj_orders o
    WHERE o.customer_id = c.customer_id
      AND o.amount > 9000
);

EXEC trace_off;

EXEC show_test_plan('T08_NO_UNNEST','Subquery Unnesting Disabled');

--------------------------------------------------------------------------------
-- T09 - PREDICATE PUSHING
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T09_PREDICATE_PUSHING');

SELECT /* T09_PREDICATE_PUSHING */
       v.customer_id,
       v.total_amount
FROM
(
    SELECT customer_id,
           SUM(amount) total_amount
    FROM oj_orders
    GROUP BY customer_id
) v
WHERE v.customer_id BETWEEN 100 AND 200;

EXEC trace_off;

EXEC show_test_plan('T09_PREDICATE_PUSHING','Predicate Pushing');

--------------------------------------------------------------------------------
-- T10 - OR EXPANSION
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T10_OR_EXPANSION');

SELECT /* T10_OR_EXPANSION */
       COUNT(*)
FROM oj_orders
WHERE customer_id = 100
   OR customer_id = 200
   OR customer_id = 300;

EXEC trace_off;

EXEC show_test_plan('T10_OR_EXPANSION','OR Expansion');

--------------------------------------------------------------------------------
-- T11 - JOIN ELIMINATION
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T11_JOIN_ELIMINATION');

SELECT /* T11_JOIN_ELIMINATION */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON c.customer_id = o.customer_id
WHERE o.amount > 9000;

EXEC trace_off;

EXEC show_test_plan('T11_JOIN_ELIMINATION','Join Elimination Candidate');

--------------------------------------------------------------------------------
-- T12 - PREDICATE TRANSITIVITY
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T12_PREDICATE_TRANSITIVITY');

SELECT /* T12_PREDICATE_TRANSITIVITY */
       COUNT(*)
FROM oj_orders o
JOIN oj_customer c
  ON o.customer_id = c.customer_id
WHERE c.customer_id = 12345;

EXEC trace_off;

EXEC show_test_plan('T12_PREDICATE_TRANSITIVITY','Predicate Transitivity');

--------------------------------------------------------------------------------
-- T13 - MISSING INDEX
-- ============================================================================
--------------------------------------------------------------------------------

DROP INDEX oj_orders_customer_i;

EXEC trace_on('T13_MISSING_INDEX');

SELECT /* T13_MISSING_INDEX */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 1 AND 10;

EXEC trace_off;

EXEC show_test_plan('T13_MISSING_INDEX','Missing Index');

CREATE INDEX oj_orders_customer_i
    ON oj_orders(customer_id);

--------------------------------------------------------------------------------
-- T14 - MISSING STATISTICS
-- ============================================================================
--------------------------------------------------------------------------------

CREATE TABLE oj_no_stats
AS
SELECT *
FROM oj_orders
WHERE 1 = 0;

INSERT INTO oj_no_stats
SELECT *
FROM oj_orders
WHERE order_id <= 100000;

COMMIT;

EXEC trace_on('T14_MISSING_STATISTICS');

SELECT /* T14_MISSING_STATISTICS */
       COUNT(*)
FROM oj_no_stats
WHERE customer_id = 100;

EXEC trace_off;

EXEC show_test_plan('T14_MISSING_STATISTICS','Missing Statistics');

--------------------------------------------------------------------------------
-- T15 - STALE STATISTICS
-- ============================================================================
--------------------------------------------------------------------------------

CREATE TABLE oj_stale
AS
SELECT *
FROM oj_skew;

BEGIN

    DBMS_STATS.GATHER_TABLE_STATS
    (
        ownname    => USER,
        tabname    => 'OJ_STALE',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO'
    );

END;
/

INSERT INTO oj_stale
SELECT id + 100000,
       skew_col,
       payload
FROM oj_skew
CROSS JOIN
(
    SELECT 1
    FROM dual
    CONNECT BY level <= 5
);

COMMIT;

EXEC trace_on('T15_STALE_STATISTICS');

SELECT /* T15_STALE_STATISTICS */
       COUNT(*)
FROM oj_stale
WHERE skew_col = 1;

EXEC trace_off;

EXEC show_test_plan('T15_STALE_STATISTICS','Stale Statistics');

--------------------------------------------------------------------------------
-- T16 - BAD TABLE STATISTICS
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN

    DBMS_STATS.SET_TABLE_STATS
    (
        ownname => USER,
        tabname => 'OJ_BIG',
        numrows => 100
    );

    DBMS_STATS.SET_TABLE_STATS
    (
        ownname => USER,
        tabname => 'OJ_SMALL',
        numrows => 100000000
    );

END;
/

EXEC trace_on('T16_BAD_TABLE_STATS');

SELECT /* T16_BAD_TABLE_STATS */
       COUNT(*)
FROM oj_big b
JOIN oj_small s
  ON s.group_id = b.group_id;

EXEC trace_off;

EXEC show_test_plan('T16_BAD_TABLE_STATS','Bad Table Statistics');

--------------------------------------------------------------------------------
-- T17 - CARDINALITY MIS-ESTIMATE
--      NO HISTOGRAM
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN

    DBMS_STATS.GATHER_TABLE_STATS
    (
        ownname    => USER,
        tabname    => 'OJ_SKEW',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE 1'
    );

END;
/

EXEC trace_on('T17_CARDINALITY_SKEW');

SELECT /* T17_CARDINALITY_SKEW */
       COUNT(*)
FROM oj_skew
WHERE skew_col = 1;

EXEC trace_off;

EXEC show_test_plan('T17_CARDINALITY_SKEW','Skewed Column Without Histogram');

--------------------------------------------------------------------------------
-- T18 - HISTOGRAM
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN

    DBMS_STATS.GATHER_TABLE_STATS
    (
        ownname    => USER,
        tabname    => 'OJ_SKEW',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE 254'
    );

END;
/

EXEC trace_on('T18_GOOD_HISTOGRAM');

SELECT /* T18_GOOD_HISTOGRAM */
       COUNT(*)
FROM oj_skew
WHERE skew_col = 1;

EXEC trace_off;

EXEC show_test_plan('T18_GOOD_HISTOGRAM','Skewed Column With Histogram');

--------------------------------------------------------------------------------
-- T19 - CLUSTERING FACTOR
-- ============================================================================
--------------------------------------------------------------------------------

CREATE TABLE oj_clustering
AS
SELECT level id,
       MOD(level,1000) col_a,
       TRUNC(level/1000) col_b,
       RPAD('CLUSTER',200,'C') payload
FROM dual
CONNECT BY level <= 500000;

CREATE INDEX oj_clustering_i
    ON oj_clustering(col_a);

BEGIN

    DBMS_STATS.GATHER_TABLE_STATS
    (
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

EXEC show_test_plan('T19_CLUSTERING_FACTOR','Clustering Factor');

PROMPT
PROMPT ============================================================
PROMPT CLUSTERING FACTOR
PROMPT ============================================================

SELECT index_name,
       table_name,
       num_rows,
       distinct_keys,
       clustering_factor
FROM user_indexes
WHERE index_name = 'OJ_CLUSTERING_I';

--------------------------------------------------------------------------------
-- T20 - SELECTIVE INDEX
-- ============================================================================
--------------------------------------------------------------------------------

CREATE INDEX oj_sales_flag_i
    ON oj_sales(flag);

BEGIN

    DBMS_STATS.GATHER_TABLE_STATS
    (
        ownname    => USER,
        tabname    => 'OJ_SALES',
        cascade    => TRUE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO'
    );

END;
/

EXEC trace_on('T20_SELECTIVE_INDEX');

SELECT /* T20_SELECTIVE_INDEX */
       COUNT(*)
FROM oj_sales
WHERE flag = 'Y';

EXEC trace_off;

EXEC show_test_plan('T20_SELECTIVE_INDEX','Selective Index');

--------------------------------------------------------------------------------
-- T21 - NON-SELECTIVE INDEX
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T21_NONSEL_INDEX');

SELECT /* T21_NONSEL_INDEX */
       COUNT(*)
FROM oj_sales
WHERE flag = 'N';

EXEC trace_off;

EXEC show_test_plan('T21_NONSEL_INDEX','Non-Selective Index');

--------------------------------------------------------------------------------
-- T22 - INDEX VS FULL TABLE SCAN
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T22_INDEX_VS_FTS');

SELECT /* T22_INDEX_VS_FTS */
       SUM(amount)
FROM oj_sales
WHERE customer_id = 12345;

EXEC trace_off;

EXEC show_test_plan('T22_INDEX_VS_FTS','Index vs Full Table Scan');

--------------------------------------------------------------------------------
-- T23 - FUNCTION ON COLUMN
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T23_FUNCTION_COLUMN');

SELECT /* T23_FUNCTION_COLUMN */
       COUNT(*)
FROM oj_orders
WHERE TRUNC(order_date) = DATE '2025-01-01';

EXEC trace_off;

EXEC show_test_plan('T23_FUNCTION_COLUMN','Function Applied to Column');

--------------------------------------------------------------------------------
-- T24 - SARGABLE PREDICATE
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T24_SARGABLE_DATE');

SELECT /* T24_SARGABLE_DATE */
       COUNT(*)
FROM oj_orders
WHERE order_date >= DATE '2025-01-01'
  AND order_date < DATE '2025-01-02';

EXEC trace_off;

EXEC show_test_plan('T24_SARGABLE_DATE','SARGable Date Predicate');

--------------------------------------------------------------------------------
-- T25 - ADAPTIVE PLAN
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN

    BEGIN
        EXECUTE IMMEDIATE
            'ALTER SESSION SET optimizer_adaptive_plans = TRUE';
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(
                'optimizer_adaptive_plans could not be set: ' ||
                SQLERRM
            );
    END;

END;
/

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

EXEC show_test_plan('T25_ADAPTIVE_FEATURES','Adaptive Plan');

--------------------------------------------------------------------------------
-- T26 - JOIN ORDER
-- ============================================================================
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

EXEC show_test_plan('T26_JOIN_ORDER','Optimizer Join Order');

--------------------------------------------------------------------------------
-- T27 - FORCED JOIN ORDER
-- ============================================================================
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

EXEC show_test_plan('T27_FORCED_JOIN_ORDER','Forced Join Order');

--------------------------------------------------------------------------------
-- T28A - FORCE NESTED LOOP
-- ============================================================================
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

EXEC show_test_plan('T28A_FORCE_NL','Forced Nested Loop');

--------------------------------------------------------------------------------
-- T28B - FORCE HASH
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T28B_FORCE_HASH');

SELECT /* T28B_FORCE_HASH */
       /*+ USE_HASH(o) */
       COUNT(*)
FROM oj_customer c
JOIN oj_orders o
  ON o.customer_id = c.customer_id
WHERE c.customer_id BETWEEN 1 AND 1000;

EXEC trace_off;

EXEC show_test_plan('T28B_FORCE_HASH','Forced Hash Join');

--------------------------------------------------------------------------------
-- T29 - COMBINED TRANSFORMATIONS
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_on('T29_COMBINED_TRANSFORMATIONS');

SELECT /* T29_COMBINED_TRANSFORMATIONS */
       v.region,
       COUNT(*)
FROM
(
    SELECT c.customer_id,
           c.region
    FROM oj_customer c
    WHERE c.status = 'ACTIVE'
      AND EXISTS
      (
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

EXEC show_test_plan('T29_COMBINED_TRANSFORMATIONS','Combined Transformations');

--------------------------------------------------------------------------------
-- T30 - BAD CARDINALITY + JOIN
-- ============================================================================
--------------------------------------------------------------------------------

BEGIN

    DBMS_STATS.SET_TABLE_STATS
    (
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

EXEC show_test_plan('T30_BAD_CARDINALITY_JOIN','Bad Cardinality + Join');

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 13 - RESULTS
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT ALL TEST RESULTS
PROMPT ============================================================

COLUMN test_id FORMAT A32
COLUMN test_description FORMAT A45
COLUMN sql_id FORMAT A13
COLUMN child_number FORMAT 999
COLUMN plan_hash_value FORMAT 9999999999
COLUMN executions FORMAT 999999
COLUMN buffer_gets FORMAT 999999999999
COLUMN disk_reads FORMAT 999999999999
COLUMN rows_processed FORMAT 999999999999

SELECT
    test_id,
    test_description,
    sql_id,
    child_number,
    plan_hash_value,
    executions,
    buffer_gets,
    disk_reads,
    rows_processed
FROM oj_trace_results
ORDER BY run_time;

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 14 - SQL_ID LOOKUP
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT TEST SQL_ID CATALOG
PROMPT ============================================================

SELECT
    test_id,
    sql_id,
    child_number,
    plan_hash_value
FROM oj_trace_results
ORDER BY test_id;

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 15 - TRACE FILE
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT TRACE FILE
PROMPT ============================================================

SELECT
    name,
    value
FROM v$diag_info
WHERE name IN
(
    'Diag Trace',
    'Default Trace File',
    'Default Trace Directory'
);

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 16 - SESSION INFORMATION
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT SESSION
PROMPT ============================================================

SELECT
    sid,
    serial#,
    sql_id,
    prev_sql_id,
    module,
    action
FROM v$session
WHERE sid = SYS_CONTEXT('USERENV','SID');

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 17 - TRACE SEARCH TERMS
-- ============================================================================
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT USEFUL 10053 TRACE SEARCH TERMS
PROMPT ============================================================
PROMPT
PROMPT Query Transformation
PROMPT CBQT
PROMPT View Merging
PROMPT Subquery Unnesting
PROMPT Predicate Move-Around
PROMPT Predicate Push
PROMPT OR Expansion
PROMPT Join Elimination
PROMPT Transitive
PROMPT Join order
PROMPT Join costing
PROMPT Access path
PROMPT Nested Loops
PROMPT Hash Join
PROMPT Sort Merge
PROMPT Cartesian
PROMPT Card
PROMPT Selectivity
PROMPT Histogram
PROMPT Clustering factor
PROMPT Dynamic sampling
PROMPT Statistics feedback
PROMPT Adaptive
PROMPT
PROMPT ============================================================

--------------------------------------------------------------------------------
-- ============================================================================
-- SECTION 18 - FINAL TRACE OFF
-- ============================================================================
--------------------------------------------------------------------------------

EXEC trace_off;

PROMPT
PROMPT ============================================================
PROMPT LAB COMPLETE
PROMPT ============================================================
PROMPT
PROMPT 10053 = optimizer decisions
PROMPT 10046 = SQL execution / waits / binds
PROMPT
PROMPT Results are stored in OJ_TRACE_RESULTS.
PROMPT
PROMPT IMPORTANT:
PROMPT The test SQL_ID is found by its LAB tag.
PROMPT DBMS_XPLAN does NOT use NULL,NULL.
PROMPT
PROMPT ============================================================
```
