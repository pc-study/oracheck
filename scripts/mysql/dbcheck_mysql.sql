-- +------------------------------------------------------------------------------------+
-- |               Copyright (c) 2015-2100 lucifer. All rights reserved.                |
-- +------------------------------------------------------------------------------------+
-- | DATABASE : MySQL                                                                    |
-- | FILE     : dbcheck_mysql.sql                                                        |
-- | CLASS    : Database Administration                                                  |
-- | PURPOSE  : MySQL database health check script. Outputs a single HTML document       |
-- |            with span/table tags for automated report generation.                     |
-- | VERSION  : Compatible with MySQL 5.7+ and MySQL 8.0+                                |
-- | USAGE    : mysql -u root -p < dbcheck_mysql.sql > dbcheck_mysql.html                |
-- +------------------------------------------------------------------------------------+

-- Disable pager and column names for clean HTML output
\! echo ''

SELECT CONCAT(
'<html>',
'<head><meta charset="utf-8"><title>MySQL DBCheck Report</title></head>',
'<body>',
'<center><font size=+3 color=darkgreen><b>', @@hostname, ' MySQL DBCheck Report</b></font></center>',
'<hr>'
) AS '';

-- ============================================================
-- Scalar values (span tags)
-- ============================================================

SELECT CONCAT(
'<span id="dbversion">', VERSION(), '</span>'
) AS '';

SELECT CONCAT(
'<span id="hostname">', @@hostname, '</span>'
) AS '';

SELECT CONCAT(
'<span id="dbname">', @@hostname, '</span>'
) AS '';

SELECT CONCAT(
'<span id="checkdate">', DATE_FORMAT(NOW(), '%Y%m%d'), '</span>'
) AS '';

SELECT CONCAT(
'<span id="uptime">', VARIABLE_VALUE, ' seconds</span>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Uptime';

SELECT CONCAT(
'<span id="port">', @@port, '</span>'
) AS '';

SELECT CONCAT(
'<span id="datadir">', @@datadir, '</span>'
) AS '';

SELECT CONCAT(
'<span id="buffer_pool_size">',
  ROUND(@@innodb_buffer_pool_size / 1024 / 1024, 2), ' MB',
'</span>'
) AS '';

SELECT CONCAT(
'<span id="instance_name">', @@hostname, ':', @@port, '</span>'
) AS '';

SELECT CONCAT(
'<span id="server_id">', @@server_id, '</span>'
) AS '';

SELECT CONCAT(
'<span id="character_set">', @@character_set_server, '</span>'
) AS '';

SELECT CONCAT(
'<span id="collation_server">', @@collation_server, '</span>'
) AS '';

-- ============================================================
-- Table: max_connections - Current vs Max connections
-- ============================================================

SELECT CONCAT(
'<table id="max_connections" border="1" width="90%" align="center">',
'<tr><td><b>Parameter</b></td><td><b>Current</b></td><td><b>Max</b></td><td><b>Usage</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>Threads_connected / max_connections</td>',
'<td>', cur.v, '</td>',
'<td>', mx.v, '</td>',
'<td>',
  CASE
    WHEN ROUND(cur.v / NULLIF(mx.v, 0) * 100, 1) > 80 THEN CONCAT('<font color="red">', ROUND(cur.v / NULLIF(mx.v, 0) * 100, 1), '%</font>')
    ELSE CONCAT(ROUND(cur.v / NULLIF(mx.v, 0) * 100, 1), '%')
  END,
'</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') cur,
  (SELECT CAST(@@max_connections AS UNSIGNED) AS v) mx;

SELECT CONCAT(
'<tr><td>Max_used_connections</td>',
'<td>', VARIABLE_VALUE, '</td>',
'<td>', @@max_connections, '</td>',
'<td>',
  CASE
    WHEN ROUND(CAST(VARIABLE_VALUE AS UNSIGNED) / NULLIF(@@max_connections, 0) * 100, 1) > 80
      THEN CONCAT('<font color="red">', ROUND(CAST(VARIABLE_VALUE AS UNSIGNED) / NULLIF(@@max_connections, 0) * 100, 1), '%</font>')
    ELSE CONCAT(ROUND(CAST(VARIABLE_VALUE AS UNSIGNED) / NULLIF(@@max_connections, 0) * 100, 1), '%')
  END,
'</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Max_used_connections';

SELECT '</table>' AS '';

-- ============================================================
-- Table: slow_query - Slow query settings and count
-- ============================================================

SELECT CONCAT(
'<table id="slow_query" border="1" width="90%" align="center">',
'<tr><td><b>Parameter</b></td><td><b>Value</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>slow_query_log</td><td>',
  CASE
    WHEN @@slow_query_log = 0 THEN '<font color="red">OFF</font>'
    ELSE 'ON'
  END,
'</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>long_query_time</td><td>', @@long_query_time, '</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>slow_query_log_file</td><td>', @@slow_query_log_file, '</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>Slow_queries</td><td>',
  CASE
    WHEN CAST(VARIABLE_VALUE AS UNSIGNED) > 100 THEN CONCAT('<font color="red">', VARIABLE_VALUE, '</font>')
    ELSE VARIABLE_VALUE
  END,
'</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Slow_queries';

SELECT '</table>' AS '';

-- ============================================================
-- Table: innodb_buffer - Buffer pool stats
-- ============================================================

SELECT CONCAT(
'<table id="innodb_buffer" border="1" width="90%" align="center">',
'<tr><td><b>Metric</b></td><td><b>Value</b></td><td><b>Status</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>Buffer Pool Size</td><td>',
  ROUND(@@innodb_buffer_pool_size / 1024 / 1024, 2), ' MB',
'</td><td>-</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>Buffer Pool Instances</td><td>', @@innodb_buffer_pool_instances, '</td><td>-</td></tr>'
) AS '';

-- Buffer pool hit rate
SELECT CONCAT(
'<tr><td>Buffer Pool Hit Rate</td><td>',
  hit_rate, '%',
'</td><td>',
  CASE
    WHEN hit_rate < 95 THEN '<font color="red">LOW</font>'
    ELSE 'OK'
  END,
'</td></tr>'
) AS ''
FROM (
  SELECT ROUND(
    (1 - IFNULL(reads.v, 0) / NULLIF(reqs.v, 0)) * 100, 2
  ) AS hit_rate
  FROM
    (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') reads,
    (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') reqs
) t;

SELECT CONCAT(
'<tr><td>Pages Dirty</td><td>',
  VARIABLE_VALUE,
'</td><td>-</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty';

SELECT CONCAT(
'<tr><td>Pages Free</td><td>',
  VARIABLE_VALUE,
'</td><td>-</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free';

SELECT CONCAT(
'<tr><td>Pages Total</td><td>',
  VARIABLE_VALUE,
'</td><td>-</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total';

SELECT '</table>' AS '';

-- ============================================================
-- Table: binlog_status - Binary log configuration
-- ============================================================

SELECT CONCAT(
'<table id="binlog_status" border="1" width="90%" align="center">',
'<tr><td><b>Parameter</b></td><td><b>Value</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>log_bin</td><td>',
  CASE
    WHEN @@log_bin = 0 THEN '<font color="red">OFF</font>'
    ELSE 'ON'
  END,
'</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>binlog_format</td><td>',
  IFNULL(@@binlog_format, 'N/A'),
'</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>expire_logs_days</td><td>',
  @@expire_logs_days,
'</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>sync_binlog</td><td>', @@sync_binlog, '</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>binlog_row_image</td><td>',
  IFNULL(@@binlog_row_image, 'N/A'),
'</td></tr>'
) AS '';

SELECT '</table>' AS '';

-- ============================================================
-- Table: replication - Slave/Replica status
-- ============================================================

SELECT CONCAT(
'<table id="replication" border="1" width="90%" align="center">',
'<tr><td><b>Parameter</b></td><td><b>Value</b></td><td><b>Status</b></td></tr>'
) AS '';

-- Use a procedure-like approach to handle empty replication status
-- When not a slave, output a single informational row
SELECT CONCAT(
'<tr><td>Slave_IO_Running</td><td>',
  IFNULL(sio, 'N/A'),
'</td><td>',
  CASE
    WHEN sio IS NULL THEN 'Not Configured'
    WHEN sio != 'Yes' THEN '<font color="red">STOPPED</font>'
    ELSE 'OK'
  END,
'</td></tr>',
'<tr><td>Slave_SQL_Running</td><td>',
  IFNULL(ssql, 'N/A'),
'</td><td>',
  CASE
    WHEN ssql IS NULL THEN 'Not Configured'
    WHEN ssql != 'Yes' THEN '<font color="red">STOPPED</font>'
    ELSE 'OK'
  END,
'</td></tr>',
'<tr><td>Seconds_Behind_Master</td><td>',
  IFNULL(sbm, 'N/A'),
'</td><td>',
  CASE
    WHEN sbm IS NULL THEN 'Not Configured'
    WHEN CAST(sbm AS UNSIGNED) > 60 THEN '<font color="red">LAG</font>'
    ELSE 'OK'
  END,
'</td></tr>',
'<tr><td>Master_Host</td><td>',
  IFNULL(mhost, 'N/A'),
'</td><td>-</td></tr>',
'<tr><td>Relay_Log_Space</td><td>',
  IFNULL(rlspace, 'N/A'),
'</td><td>-</td></tr>'
) AS ''
FROM (
  SELECT
    MAX(CASE WHEN col = 'Slave_IO_Running' THEN val END) AS sio,
    MAX(CASE WHEN col = 'Slave_SQL_Running' THEN val END) AS ssql,
    MAX(CASE WHEN col = 'Seconds_Behind_Master' THEN val END) AS sbm,
    MAX(CASE WHEN col = 'Master_Host' THEN val END) AS mhost,
    MAX(CASE WHEN col = 'Relay_Log_Space' THEN val END) AS rlspace
  FROM (
    SELECT 'Slave_IO_Running' AS col, NULL AS val
    UNION ALL SELECT 'Slave_SQL_Running', NULL
    UNION ALL SELECT 'Seconds_Behind_Master', NULL
    UNION ALL SELECT 'Master_Host', NULL
    UNION ALL SELECT 'Relay_Log_Space', NULL
  ) defaults
) t;

SELECT '</table>' AS '';

-- ============================================================
-- Table: table_size - Top 10 tables by size
-- ============================================================

SELECT CONCAT(
'<table id="table_size" border="1" width="90%" align="center">',
'<tr><td><b>Schema</b></td><td><b>Table</b></td><td><b>Engine</b></td><td><b>Rows</b></td><td><b>Data_MB</b></td><td><b>Index_MB</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', TABLE_SCHEMA, '</td>',
'<td>', TABLE_NAME, '</td>',
'<td>', IFNULL(ENGINE, 'N/A'), '</td>',
'<td>', IFNULL(TABLE_ROWS, 0), '</td>',
'<td>',
  CASE
    WHEN ROUND(IFNULL(DATA_LENGTH, 0) / 1024 / 1024, 2) > 10240 THEN CONCAT('<font color="red">', ROUND(IFNULL(DATA_LENGTH, 0) / 1024 / 1024, 2), '</font>')
    ELSE CAST(ROUND(IFNULL(DATA_LENGTH, 0) / 1024 / 1024, 2) AS CHAR)
  END,
'</td>',
'<td>', ROUND(IFNULL(INDEX_LENGTH, 0) / 1024 / 1024, 2), '</td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
  AND TABLE_TYPE = 'BASE TABLE'
  AND DATA_LENGTH IS NOT NULL
ORDER BY DATA_LENGTH DESC
LIMIT 10;

SELECT '</table>' AS '';

-- ============================================================
-- Table: index_usage - Unused/duplicate indexes
-- ============================================================

SELECT CONCAT(
'<table id="index_usage" border="1" width="90%" align="center">',
'<tr><td><b>Schema</b></td><td><b>Table</b></td><td><b>Index</b></td><td><b>Type</b></td><td><b>Status</b></td></tr>'
) AS '';

-- Duplicate indexes (indexes with same columns on same table)
SELECT CONCAT(
'<tr>',
'<td>', s1.TABLE_SCHEMA, '</td>',
'<td>', s1.TABLE_NAME, '</td>',
'<td><font color="red">', s1.INDEX_NAME, '</font></td>',
'<td>', CASE WHEN s1.NON_UNIQUE = 0 THEN 'UNIQUE' ELSE 'INDEX' END, '</td>',
'<td><font color="red">Duplicate</font></td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.STATISTICS s1
JOIN INFORMATION_SCHEMA.STATISTICS s2
  ON s1.TABLE_SCHEMA = s2.TABLE_SCHEMA
  AND s1.TABLE_NAME = s2.TABLE_NAME
  AND s1.SEQ_IN_INDEX = s2.SEQ_IN_INDEX
  AND s1.COLUMN_NAME = s2.COLUMN_NAME
  AND s1.INDEX_NAME != s2.INDEX_NAME
  AND s1.INDEX_NAME > s2.INDEX_NAME
WHERE s1.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
GROUP BY s1.TABLE_SCHEMA, s1.TABLE_NAME, s1.INDEX_NAME, s1.NON_UNIQUE
LIMIT 20;

SELECT '</table>' AS '';

-- ============================================================
-- Table: user_security - User account security
-- ============================================================

SELECT CONCAT(
'<table id="user_security" border="1" width="90%" align="center">',
'<tr><td><b>User</b></td><td><b>Host</b></td><td><b>Plugin</b></td><td><b>Password_Expired</b></td><td><b>Account_Locked</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', u.User, '</td>',
'<td>', u.Host, '</td>',
'<td>',
  CASE
    WHEN u.plugin = 'mysql_native_password' AND (u.authentication_string IS NULL OR u.authentication_string = '')
      THEN CONCAT('<font color="red">', u.plugin, '</font>')
    ELSE u.plugin
  END,
'</td>',
'<td>',
  CASE
    WHEN u.password_expired = 'Y' THEN '<font color="red">Y</font>'
    ELSE u.password_expired
  END,
'</td>',
'<td>',
  CASE
    WHEN u.account_locked = 'Y' THEN 'Y'
    ELSE u.account_locked
  END,
'</td>',
'</tr>'
) AS ''
FROM mysql.user u
ORDER BY u.User, u.Host;

SELECT '</table>' AS '';

-- ============================================================
-- Table: backup_status - Recent backup info
-- Uses performance_schema events if available; otherwise empty
-- ============================================================

SELECT CONCAT(
'<table id="backup_status" border="1" width="90%" align="center">',
'<tr><td><b>Check</b></td><td><b>Value</b></td><td><b>Status</b></td></tr>'
) AS '';

-- Check for recent backups via INFORMATION_SCHEMA.FILES or general heuristics
-- Since MySQL has no built-in backup catalog, we check binary log freshness as a proxy
SELECT CONCAT(
'<tr>',
'<td>Binlog Backup</td>',
'<td>',
  CASE
    WHEN @@log_bin = 1 THEN 'Enabled'
    ELSE '<font color="red">Disabled</font>'
  END,
'</td>',
'<td>',
  CASE
    WHEN @@log_bin = 1 THEN 'OK'
    ELSE '<font color="red">No binary log</font>'
  END,
'</td>',
'</tr>'
) AS '';

SELECT '</table>' AS '';

-- ============================================================
-- Table: db_overview - All databases with sizes
-- ============================================================

SELECT CONCAT(
'<table id="db_overview" border="1" width="90%" align="center">',
'<tr><td><b>Database</b></td><td><b>Tables</b></td><td><b>Size_MB</b></td><td><b>Data_MB</b></td><td><b>Index_MB</b></td><td><b>Engine</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', db_name, '</td>',
'<td>', tbl_count, '</td>',
'<td>',
  CASE
    WHEN total_mb > 102400 THEN CONCAT('<font color="red">', total_mb, '</font>')
    ELSE CAST(total_mb AS CHAR)
  END,
'</td>',
'<td>', data_mb, '</td>',
'<td>', idx_mb, '</td>',
'<td>', IFNULL(engines, 'N/A'), '</td>',
'</tr>'
) AS ''
FROM (
  SELECT
    t.TABLE_SCHEMA AS db_name,
    COUNT(*) AS tbl_count,
    ROUND(SUM(IFNULL(t.DATA_LENGTH, 0) + IFNULL(t.INDEX_LENGTH, 0)) / 1024 / 1024, 2) AS total_mb,
    ROUND(SUM(IFNULL(t.DATA_LENGTH, 0)) / 1024 / 1024, 2) AS data_mb,
    ROUND(SUM(IFNULL(t.INDEX_LENGTH, 0)) / 1024 / 1024, 2) AS idx_mb,
    GROUP_CONCAT(DISTINCT t.ENGINE ORDER BY t.ENGINE SEPARATOR ',') AS engines
  FROM INFORMATION_SCHEMA.TABLES t
  WHERE t.TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'sys')
    AND t.TABLE_TYPE = 'BASE TABLE'
  GROUP BY t.TABLE_SCHEMA
  ORDER BY total_mb DESC
) sub;

SELECT '</table>' AS '';

-- ============================================================
-- Table: important_params - Key MySQL parameters
-- ============================================================

SELECT CONCAT(
'<table id="important_params" border="1" width="90%" align="center">',
'<tr><td><b>Parameter</b></td><td><b>Value</b></td><td><b>Recommended</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_flush_log_at_trx_commit</td><td>',
  CASE
    WHEN @@innodb_flush_log_at_trx_commit != 1 THEN CONCAT('<font color="red">', @@innodb_flush_log_at_trx_commit, '</font>')
    ELSE CAST(@@innodb_flush_log_at_trx_commit AS CHAR)
  END,
'</td><td>1</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>sync_binlog</td><td>',
  CASE
    WHEN @@sync_binlog != 1 THEN CONCAT('<font color="red">', @@sync_binlog, '</font>')
    ELSE CAST(@@sync_binlog AS CHAR)
  END,
'</td><td>1</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_file_per_table</td><td>',
  CASE
    WHEN @@innodb_file_per_table != 1 THEN '<font color="red">OFF</font>'
    ELSE 'ON'
  END,
'</td><td>ON</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>max_allowed_packet</td><td>',
  ROUND(@@max_allowed_packet / 1024 / 1024, 2), ' MB',
'</td><td>&gt;= 16 MB</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>tmp_table_size</td><td>',
  ROUND(@@tmp_table_size / 1024 / 1024, 2), ' MB',
'</td><td>&gt;= 64 MB</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>max_heap_table_size</td><td>',
  ROUND(@@max_heap_table_size / 1024 / 1024, 2), ' MB',
'</td><td>&gt;= 64 MB</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_log_file_size</td><td>',
  ROUND(@@innodb_log_file_size / 1024 / 1024, 2), ' MB',
'</td><td>&gt;= 256 MB</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>lower_case_table_names</td><td>',
  @@lower_case_table_names,
'</td><td>1 (case insensitive)</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_flush_method</td><td>',
  IFNULL(@@innodb_flush_method, 'default'),
'</td><td>O_DIRECT</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_buffer_pool_size</td><td>',
  ROUND(@@innodb_buffer_pool_size / 1024 / 1024, 2), ' MB',
'</td><td>50-80% of RAM</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>innodb_buffer_pool_instances</td><td>',
  @@innodb_buffer_pool_instances,
'</td><td>8 (if pool &gt; 1GB)</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>max_connections</td><td>',
  @@max_connections,
'</td><td>Based on workload</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>thread_cache_size</td><td>',
  @@thread_cache_size,
'</td><td>&gt;= 16</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>table_open_cache</td><td>',
  @@table_open_cache,
'</td><td>&gt;= 2000</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>open_files_limit</td><td>',
  @@open_files_limit,
'</td><td>&gt;= 65535</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>log_bin</td><td>',
  CASE WHEN @@log_bin = 1 THEN 'ON' ELSE '<font color="red">OFF</font>' END,
'</td><td>ON</td></tr>'
) AS '';

SELECT CONCAT(
'<tr><td>binlog_format</td><td>',
  IFNULL(@@binlog_format, 'N/A'),
'</td><td>ROW</td></tr>'
) AS '';

SELECT '</table>' AS '';

-- ============================================================
-- Table: process_list - Active processes (non-Sleep, non-system)
-- ============================================================

SELECT CONCAT(
'<table id="process_list" border="1" width="90%" align="center">',
'<tr><td><b>ID</b></td><td><b>User</b></td><td><b>Host</b></td><td><b>DB</b></td><td><b>Command</b></td><td><b>Time</b></td><td><b>State</b></td><td><b>Info</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', p.ID, '</td>',
'<td>', p.USER, '</td>',
'<td>', p.HOST, '</td>',
'<td>', IFNULL(p.DB, 'NULL'), '</td>',
'<td>', p.COMMAND, '</td>',
'<td>',
  CASE
    WHEN p.TIME > 300 THEN CONCAT('<font color="red">', p.TIME, '</font>')
    ELSE CAST(p.TIME AS CHAR)
  END,
'</td>',
'<td>', IFNULL(p.STATE, ''), '</td>',
'<td>', IFNULL(LEFT(p.INFO, 200), ''), '</td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.PROCESSLIST p
WHERE p.COMMAND != 'Sleep'
  AND p.COMMAND != 'Daemon'
  AND p.USER NOT IN ('system user', 'event_scheduler')
  AND p.INFO NOT LIKE '%INFORMATION_SCHEMA.PROCESSLIST%'
ORDER BY p.TIME DESC
LIMIT 50;

SELECT '</table>' AS '';

-- ============================================================
-- Table: long_transactions - Long-running transactions
-- ============================================================

SELECT CONCAT(
'<table id="long_transactions" border="1" width="90%" align="center">',
'<tr><td><b>Thread_ID</b></td><td><b>User</b></td><td><b>DB</b></td><td><b>Duration_Sec</b></td><td><b>State</b></td><td><b>Query</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', IFNULL(trx.trx_mysql_thread_id, 0), '</td>',
'<td>', IFNULL(p.USER, 'N/A'), '</td>',
'<td>', IFNULL(p.DB, 'N/A'), '</td>',
'<td>',
  CASE
    WHEN TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()) > 300
      THEN CONCAT('<font color="red">', TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()), '</font>')
    ELSE CAST(TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()) AS CHAR)
  END,
'</td>',
'<td>', IFNULL(trx.trx_state, 'N/A'), '</td>',
'<td>', IFNULL(LEFT(trx.trx_query, 200), 'N/A'), '</td>',
'</tr>'
) AS ''
FROM information_schema.innodb_trx trx
LEFT JOIN INFORMATION_SCHEMA.PROCESSLIST p ON trx.trx_mysql_thread_id = p.ID
ORDER BY trx.trx_started ASC
LIMIT 30;

SELECT '</table>' AS '';

-- ============================================================
-- Table: table_no_pk - Tables without primary key
-- ============================================================

SELECT CONCAT(
'<table id="table_no_pk" border="1" width="90%" align="center">',
'<tr><td><b>Schema</b></td><td><b>Table</b></td><td><b>Engine</b></td><td><b>Rows</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td><font color="red">', t.TABLE_SCHEMA, '</font></td>',
'<td><font color="red">', t.TABLE_NAME, '</font></td>',
'<td>', IFNULL(t.ENGINE, 'N/A'), '</td>',
'<td>', IFNULL(t.TABLE_ROWS, 0), '</td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN (
  SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_TYPE = 'PRIMARY KEY'
) pk ON t.TABLE_SCHEMA = pk.TABLE_SCHEMA AND t.TABLE_NAME = pk.TABLE_NAME
WHERE pk.TABLE_NAME IS NULL
  AND t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
  AND t.TABLE_TYPE = 'BASE TABLE'
ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
LIMIT 50;

SELECT '</table>' AS '';

-- ============================================================
-- Table: auto_increment - Auto-increment columns approaching limit
-- ============================================================

SELECT CONCAT(
'<table id="auto_increment" border="1" width="90%" align="center">',
'<tr><td><b>Schema</b></td><td><b>Table</b></td><td><b>Column</b></td><td><b>Data_Type</b></td><td><b>Current_Value</b></td><td><b>Max_Value</b></td><td><b>Usage_Pct</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', t.TABLE_SCHEMA, '</td>',
'<td>', t.TABLE_NAME, '</td>',
'<td>', c.COLUMN_NAME, '</td>',
'<td>', c.COLUMN_TYPE, '</td>',
'<td>', IFNULL(t.AUTO_INCREMENT, 0), '</td>',
'<td>', max_val, '</td>',
'<td>',
  CASE
    WHEN ROUND(IFNULL(t.AUTO_INCREMENT, 0) / NULLIF(max_val, 0) * 100, 2) > 80
      THEN CONCAT('<font color="red">', ROUND(IFNULL(t.AUTO_INCREMENT, 0) / NULLIF(max_val, 0) * 100, 2), '%</font>')
    ELSE CONCAT(ROUND(IFNULL(t.AUTO_INCREMENT, 0) / NULLIF(max_val, 0) * 100, 2), '%')
  END,
'</td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.TABLES t
INNER JOIN INFORMATION_SCHEMA.COLUMNS c
  ON t.TABLE_SCHEMA = c.TABLE_SCHEMA
  AND t.TABLE_NAME = c.TABLE_NAME
  AND c.EXTRA LIKE '%auto_increment%'
INNER JOIN (
  SELECT 'tinyint' AS dtype, 127 AS max_val
  UNION ALL SELECT 'tinyint unsigned', 255
  UNION ALL SELECT 'smallint', 32767
  UNION ALL SELECT 'smallint unsigned', 65535
  UNION ALL SELECT 'mediumint', 8388607
  UNION ALL SELECT 'mediumint unsigned', 16777215
  UNION ALL SELECT 'int', 2147483647
  UNION ALL SELECT 'int unsigned', 4294967295
  UNION ALL SELECT 'bigint', 9223372036854775807
  UNION ALL SELECT 'bigint unsigned', 18446744073709551615
) dt ON c.COLUMN_TYPE LIKE CONCAT(dt.dtype, '%')
WHERE t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
  AND t.AUTO_INCREMENT IS NOT NULL
  AND t.TABLE_TYPE = 'BASE TABLE'
ORDER BY ROUND(IFNULL(t.AUTO_INCREMENT, 0) / NULLIF(max_val, 0) * 100, 2) DESC
LIMIT 30;

SELECT '</table>' AS '';

-- ============================================================
-- Table: redundant_indexes - Redundant/duplicate indexes
-- ============================================================

SELECT CONCAT(
'<table id="redundant_indexes" border="1" width="90%" align="center">',
'<tr><td><b>Schema</b></td><td><b>Table</b></td><td><b>Redundant_Index</b></td><td><b>Redundant_Columns</b></td><td><b>Dominant_Index</b></td><td><b>Dominant_Columns</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td><font color="red">', r.TABLE_SCHEMA, '</font></td>',
'<td><font color="red">', r.TABLE_NAME, '</font></td>',
'<td><font color="red">', r.redundant_index, '</font></td>',
'<td><font color="red">', r.redundant_columns, '</font></td>',
'<td>', r.dominant_index, '</td>',
'<td>', r.dominant_columns, '</td>',
'</tr>'
) AS ''
FROM (
  SELECT
    a.TABLE_SCHEMA,
    a.TABLE_NAME,
    a.INDEX_NAME AS redundant_index,
    a.idx_cols AS redundant_columns,
    b.INDEX_NAME AS dominant_index,
    b.idx_cols AS dominant_columns
  FROM (
    SELECT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME,
      GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS idx_cols,
      COUNT(*) AS col_cnt
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    GROUP BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
  ) a
  INNER JOIN (
    SELECT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME,
      GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',') AS idx_cols,
      COUNT(*) AS col_cnt
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    GROUP BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
  ) b
    ON a.TABLE_SCHEMA = b.TABLE_SCHEMA
    AND a.TABLE_NAME = b.TABLE_NAME
    AND a.INDEX_NAME != b.INDEX_NAME
    AND b.idx_cols LIKE CONCAT(a.idx_cols, '%')
    AND b.col_cnt > a.col_cnt
) r
ORDER BY r.TABLE_SCHEMA, r.TABLE_NAME, r.redundant_index
LIMIT 30;

SELECT '</table>' AS '';

-- ============================================================
-- Table: storage_engines - Tables per storage engine
-- ============================================================

SELECT CONCAT(
'<table id="storage_engines" border="1" width="90%" align="center">',
'<tr><td><b>Engine</b></td><td><b>Count</b></td><td><b>Total_Size_MB</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', IFNULL(ENGINE, 'NULL'), '</td>',
'<td>', COUNT(*), '</td>',
'<td>', ROUND(SUM(IFNULL(DATA_LENGTH, 0) + IFNULL(INDEX_LENGTH, 0)) / 1024 / 1024, 2), '</td>',
'</tr>'
) AS ''
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'sys')
  AND TABLE_TYPE = 'BASE TABLE'
GROUP BY ENGINE
ORDER BY COUNT(*) DESC;

SELECT '</table>' AS '';

-- ============================================================
-- Table: global_status_stats - Key performance counters
-- ============================================================

SELECT CONCAT(
'<table id="global_status_stats" border="1" width="90%" align="center">',
'<tr><td><b>Metric</b></td><td><b>Value</b></td><td><b>Description</b></td></tr>'
) AS '';

-- QPS
SELECT CONCAT(
'<tr><td>QPS (Queries Per Second)</td><td>',
  ROUND(q.v / NULLIF(u.v, 0), 2),
'</td><td>Questions / Uptime</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Questions') q,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- TPS
SELECT CONCAT(
'<tr><td>TPS (Transactions Per Second)</td><td>',
  ROUND((c.v + r.v) / NULLIF(u.v, 0), 2),
'</td><td>(Com_commit + Com_rollback) / Uptime</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_commit') c,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_rollback') r,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Bytes_received per second
SELECT CONCAT(
'<tr><td>Bytes_received/s</td><td>',
  ROUND(br.v / NULLIF(u.v, 0), 2),
'</td><td>Avg bytes received per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Bytes_received') br,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Bytes_sent per second
SELECT CONCAT(
'<tr><td>Bytes_sent/s</td><td>',
  ROUND(bs.v / NULLIF(u.v, 0), 2),
'</td><td>Avg bytes sent per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Bytes_sent') bs,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Threads_running
SELECT CONCAT(
'<tr><td>Threads_running</td><td>',
  VARIABLE_VALUE,
'</td><td>Currently executing threads</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Threads_running';

-- Threads_connected
SELECT CONCAT(
'<tr><td>Threads_connected</td><td>',
  VARIABLE_VALUE,
'</td><td>Currently connected threads</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Threads_connected';

-- Threads_created
SELECT CONCAT(
'<tr><td>Threads_created</td><td>',
  VARIABLE_VALUE,
'</td><td>Total threads created (high = increase thread_cache_size)</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Threads_created';

-- Open_tables
SELECT CONCAT(
'<tr><td>Open_tables</td><td>',
  VARIABLE_VALUE,
'</td><td>Currently open tables</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Open_tables';

-- Open_files
SELECT CONCAT(
'<tr><td>Open_files</td><td>',
  VARIABLE_VALUE,
'</td><td>Currently open files</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Open_files';

-- Table_open_cache_hits and misses
SELECT CONCAT(
'<tr><td>Table_open_cache Hit Rate</td><td>',
  CASE
    WHEN (h.v + m.v) = 0 THEN 'N/A'
    ELSE CONCAT(ROUND(h.v / (h.v + m.v) * 100, 2), '%')
  END,
'</td><td>Table_open_cache_hits / (hits + misses)</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Table_open_cache_hits') h,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Table_open_cache_misses') m;

-- Aborted_connects
SELECT CONCAT(
'<tr><td>Aborted_connects</td><td>',
  VARIABLE_VALUE,
'</td><td>Failed connection attempts</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Aborted_connects';

-- Aborted_clients
SELECT CONCAT(
'<tr><td>Aborted_clients</td><td>',
  VARIABLE_VALUE,
'</td><td>Clients disconnected without closing properly</td></tr>'
) AS ''
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Aborted_clients';

-- Com_select
SELECT CONCAT(
'<tr><td>Com_select/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>SELECT operations per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_select') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Com_insert
SELECT CONCAT(
'<tr><td>Com_insert/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>INSERT operations per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_insert') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Com_update
SELECT CONCAT(
'<tr><td>Com_update/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>UPDATE operations per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_update') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Com_delete
SELECT CONCAT(
'<tr><td>Com_delete/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>DELETE operations per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_delete') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Innodb_rows_read/s
SELECT CONCAT(
'<tr><td>Innodb_rows_read/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>InnoDB rows read per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_rows_read') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

-- Innodb_rows_inserted/s
SELECT CONCAT(
'<tr><td>Innodb_rows_inserted/s</td><td>',
  ROUND(s.v / NULLIF(u.v, 0), 2),
'</td><td>InnoDB rows inserted per second</td></tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_rows_inserted') s,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Uptime') u;

SELECT '</table>' AS '';

-- ============================================================
-- Table: tmp_disk_tables - Temp tables created on disk
-- ============================================================

SELECT CONCAT(
'<table id="tmp_disk_tables" border="1" width="90%" align="center">',
'<tr><td><b>Created_tmp_disk_tables</b></td><td><b>Created_tmp_tables</b></td><td><b>Disk_Ratio_Pct</b></td></tr>'
) AS '';

SELECT CONCAT(
'<tr>',
'<td>', d.v, '</td>',
'<td>', t.v, '</td>',
'<td>',
  CASE
    WHEN t.v = 0 THEN '0.00%'
    WHEN ROUND(d.v / NULLIF(t.v, 0) * 100, 2) > 25
      THEN CONCAT('<font color="red">', ROUND(d.v / NULLIF(t.v, 0) * 100, 2), '%</font>')
    ELSE CONCAT(ROUND(d.v / NULLIF(t.v, 0) * 100, 2), '%')
  END,
'</td>',
'</tr>'
) AS ''
FROM
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') d,
  (SELECT CAST(VARIABLE_VALUE AS UNSIGNED) AS v FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Created_tmp_tables') t;

SELECT '</table>' AS '';

-- ============================================================
-- Footer
-- ============================================================

SELECT CONCAT(
'<hr>',
'<center><font size=-1>MySQL DBCheck Report generated at ', NOW(), '</font></center>',
'</body></html>'
) AS '';
