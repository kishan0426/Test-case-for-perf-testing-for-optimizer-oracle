--------------------------------------------------------------------------------
-- ORACLE 23ai OPTIMIZER TRACE LAB
-- CLEANUP SCRIPT
--
-- Removes objects created by the Optimizer / 10053 / 10046 lab.
--
-- Run as the SAME schema that ran the lab.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK ON

PROMPT
PROMPT ============================================================
PROMPT 1. DISABLE 10053 AND 10046 TRACING
PROMPT ============================================================
PROMPT

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10053 trace name context off''';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('10053 cleanup: ' || SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET EVENTS ''10046 trace name context off''';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('10046 cleanup: ' || SQLERRM);
END;
/

PROMPT
PROMPT Tracing disabled.
PROMPT


--------------------------------------------------------------------------------
-- 2. DROP LAB PROCEDURES
--------------------------------------------------------------------------------

PROMPT ============================================================
PROMPT 2. DROP HELPER PROCEDURES
PROMPT ============================================================

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE TRACE_ON';
    DBMS_OUTPUT.PUT_LINE('Dropped TRACE_ON');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            DBMS_OUTPUT.PUT_LINE('TRACE_ON: ' || SQLERRM);
        END IF;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE TRACE_OFF';
    DBMS_OUTPUT.PUT_LINE('Dropped TRACE_OFF');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -4043 THEN
            DBMS_OUTPUT.PUT_LINE('TRACE_OFF: ' || SQLERRM);
        END IF;
END;
/

--------------------------------------------------------------------------------
-- 3. DROP TABLES
--
-- CASCADE CONSTRAINTS also removes dependent constraints.
-- PURGE prevents objects from going to the recycle bin.
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT 3. DROP LAB TABLES
PROMPT ============================================================
PROMPT

BEGIN
    FOR r IN (
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
            'OJ_SKEW',
            'OJ_NO_STATS',
            'OJ_STALE',
            'OJ_CLUSTERING'
        )
        ORDER BY table_name
    )
    LOOP
        BEGIN
            EXECUTE IMMEDIATE
                'DROP TABLE ' || r.table_name ||
                ' CASCADE CONSTRAINTS PURGE';

            DBMS_OUTPUT.PUT_LINE(
                'Dropped table: ' || r.table_name
            );

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    'Could not drop ' || r.table_name ||
                    ': ' || SQLERRM
                );
        END;
    END LOOP;
END;
/

--------------------------------------------------------------------------------
-- 4. OPTIONAL: REMOVE ANY REMAINING LAB INDEXES
--
-- Normally unnecessary because dropping the tables removes the indexes.
-- This section is useful if an index was created independently.
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT 4. DROP REMAINING LAB INDEXES
PROMPT ============================================================

BEGIN
    FOR r IN (
        SELECT index_name
        FROM user_indexes
        WHERE index_name IN (
            'OJ_EMP_DEPT_I',
            'OJ_EMP_STATUS_I',
            'OJ_ORDERS_CUSTOMER_I',
            'OJ_ORDERS_DATE_I',
            'OJ_ORDERS_STATUS_I',
            'OJ_ORDER_ITEMS_PRODUCT_I',
            'OJ_SALES_CUSTOMER_I',
            'OJ_SALES_DATE_I',
            'OJ_SALES_REGION_I',
            'OJ_SALES_FLAG_I',
            'OJ_BIG_GROUP_I',
            'OJ_SMALL_GROUP_I',
            'OJ_SKEW_COL_I',
            'OJ_CLUSTERING_I'
        )
    )
    LOOP
        BEGIN
            EXECUTE IMMEDIATE
                'DROP INDEX ' || r.index_name;

            DBMS_OUTPUT.PUT_LINE(
                'Dropped index: ' || r.index_name
            );

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    'Could not drop ' || r.index_name ||
                    ': ' || SQLERRM
                );
        END;
    END LOOP;
END;
/

--------------------------------------------------------------------------------
-- 5. RESET SESSION OPTIMIZER SETTINGS
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT 5. RESET SESSION SETTINGS
PROMPT ============================================================

ALTER SESSION SET statistics_level = TYPICAL;

--------------------------------------------------------------------------------
-- These may fail on some configurations/versions if a parameter is not
-- available or is controlled differently. Ignore such errors if applicable.
--------------------------------------------------------------------------------

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET optimizer_adaptive_plans = TRUE';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
            'optimizer_adaptive_plans reset: ' || SQLERRM
        );
END;
/

BEGIN
    EXECUTE IMMEDIATE
        'ALTER SESSION SET optimizer_adaptive_statistics = FALSE';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
            'optimizer_adaptive_statistics reset: ' || SQLERRM
        );
END;
/

--------------------------------------------------------------------------------
-- 6. VERIFY OBJECT CLEANUP
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT 6. VERIFY TABLE CLEANUP
PROMPT ============================================================

SELECT table_name
FROM user_tables
WHERE table_name LIKE 'OJ_%'
ORDER BY table_name;

PROMPT
PROMPT ============================================================
PROMPT 7. VERIFY INDEX CLEANUP
PROMPT ============================================================

SELECT index_name,
       table_name
FROM user_indexes
WHERE index_name LIKE 'OJ_%'
ORDER BY index_name;

PROMPT
PROMPT ============================================================
PROMPT 8. VERIFY PROCEDURE CLEANUP
PROMPT ============================================================

SELECT object_name,
       object_type,
       status
FROM user_objects
WHERE object_name IN ('TRACE_ON','TRACE_OFF');

--------------------------------------------------------------------------------
-- 9. TRACE FILE INFORMATION
--
-- This does NOT delete trace files.
--
-- Trace files are managed by Oracle's diagnostic infrastructure.
-- If you need to remove old trace files, use ADRCI at the OS level
-- rather than trying to delete them from SQL.
--------------------------------------------------------------------------------

PROMPT
PROMPT ============================================================
PROMPT 9. CURRENT TRACE LOCATION
PROMPT ============================================================

SELECT name,
       value
FROM v$diag_info
WHERE name IN (
    'Diag Trace',
    'Default Trace File',
    'Default Trace Directory'
);

PROMPT
PROMPT ============================================================
PROMPT CLEANUP COMPLETE
PROMPT ============================================================
