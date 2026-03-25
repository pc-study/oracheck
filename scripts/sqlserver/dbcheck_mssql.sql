-- +------------------------------------------------------------------------------------+
-- |               Copyright (c) 2015-2100 lucifer. All rights reserved.               |
-- +------------------------------------------------------------------------------------+
-- | DATABASE : SQL Server                                                              |
-- | FILE     : dbcheck_mssql.sql                                                       |
-- | CLASS    : Database Administration                                                 |
-- | PURPOSE  : This T-SQL script provides a detailed report (in HTML format) on        |
-- |            all database metrics including storage, performance, security,           |
-- |            backup status, and availability group health.                            |
-- | VERSION  : This script was designed for SQL Server 2016+.                          |
-- | USAGE    :                                                                         |
-- |   sqlcmd -S <server> -d master -i dbcheck_mssql.sql -o dbcheck_mssql.html          |
-- |                                                                                    |
-- | NOTE     : Run with sysadmin or equivalent privileges.                             |
-- +------------------------------------------------------------------------------------+

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- ============================================================================
-- Helper: We build the entire HTML document in @html and print at the end.
-- Using NVARCHAR(MAX) throughout to avoid truncation.
-- ============================================================================

DECLARE @html NVARCHAR(MAX) = N'';
DECLARE @section NVARCHAR(MAX) = N'';
DECLARE @crlf NVARCHAR(2) = CHAR(13) + CHAR(10);

-- ============================================================================
-- Collect scalar values
-- ============================================================================
DECLARE @dbversion NVARCHAR(512);
DECLARE @hostname NVARCHAR(256);
DECLARE @dbname NVARCHAR(256);
DECLARE @checkdate NVARCHAR(20);
DECLARE @uptime NVARCHAR(128);
DECLARE @port NVARCHAR(20);
DECLARE @edition NVARCHAR(256);
DECLARE @collation NVARCHAR(256);
DECLARE @product_level NVARCHAR(128);
DECLARE @server_memory NVARCHAR(128);
DECLARE @cpu_count NVARCHAR(20);

SET @dbversion = @@VERSION;
SET @hostname = CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(256));
SET @dbname = CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(256));
IF @dbname IS NULL SET @dbname = N'MSSQLSERVER';
SET @checkdate = CONVERT(NVARCHAR(20), GETDATE(), 23); -- YYYY-MM-DD
SET @edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(256));
SET @collation = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(256));
SET @product_level = CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128));

-- Server memory and CPU
BEGIN TRY
    SELECT @server_memory = CAST(CAST(physical_memory_kb / 1024.0 AS DECIMAL(18,0)) AS NVARCHAR(128)) + N' MB',
           @cpu_count = CAST(cpu_count AS NVARCHAR(20))
    FROM sys.dm_os_sys_info;
END TRY
BEGIN CATCH
    SET @server_memory = N'N/A';
    SET @cpu_count = N'N/A';
END CATCH

-- Uptime
BEGIN TRY
    DECLARE @start_time DATETIME;
    SELECT @start_time = sqlserver_start_time FROM sys.dm_os_sys_info;
    SET @uptime = CONVERT(NVARCHAR(20), @start_time, 120)
        + N' (up '
        + CAST(DATEDIFF(DAY, @start_time, GETDATE()) AS NVARCHAR(10))
        + N' days)';
END TRY
BEGIN CATCH
    SET @uptime = N'N/A';
END CATCH

-- TCP Port
BEGIN TRY
    SELECT @port = CAST(local_tcp_port AS NVARCHAR(20))
    FROM sys.dm_exec_connections
    WHERE session_id = @@SPID;
    IF @port IS NULL SET @port = N'N/A';
END TRY
BEGIN CATCH
    SET @port = N'N/A';
END CATCH

-- ============================================================================
-- HTML Header + Scalar Spans
-- ============================================================================
SET @html = @html
    + N'<html><head><meta charset="utf-8"><title>SQL Server DBCheck Report</title></head><body>' + @crlf
    + N'<center><font size="+3" color="darkgreen"><b>' + @dbname + N' DBCheck Report</b></font></center>' + @crlf
    + N'<hr>' + @crlf
    + N'<span id="dbversion">' + REPLACE(@dbversion, CHAR(10), ' ') + N'</span>' + @crlf
    + N'<span id="hostname">' + @hostname + N'</span>' + @crlf
    + N'<span id="dbname">' + @dbname + N'</span>' + @crlf
    + N'<span id="checkdate">' + @checkdate + N'</span>' + @crlf
    + N'<span id="uptime">' + @uptime + N'</span>' + @crlf
    + N'<span id="port">' + @port + N'</span>' + @crlf
    + N'<span id="edition">' + @edition + N'</span>' + @crlf
    + N'<span id="collation">' + @collation + N'</span>' + @crlf
    + N'<span id="product_level">' + @product_level + N'</span>' + @crlf
    + N'<span id="server_memory">' + @server_memory + N'</span>' + @crlf
    + N'<span id="cpu_count">' + @cpu_count + N'</span>' + @crlf
    + N'<hr>' + @crlf;

-- ============================================================================
-- 1. filegroup_usage - Database file/filegroup usage
-- Columns: Database, FileGroup, File, Size_MB, Used_MB, Free_MB, Usage%
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + d.name + N'</td>'
        + N'<td>' + ISNULL(fg.name, N'LOG') + N'</td>'
        + N'<td>' + mf.name + N'</td>'
        + N'<td>' + CAST(CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST((mf.size - FILEPROPERTY(mf.name, 'SpaceUsed')) * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + CASE
            WHEN mf.size > 0 AND CAST(FILEPROPERTY(mf.name, 'SpaceUsed') AS FLOAT) / CAST(mf.size AS FLOAT) * 100 >= 90
            THEN N'<td><font color="red"><b>' + CAST(CAST(FILEPROPERTY(mf.name, 'SpaceUsed') * 100.0 / mf.size AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CAST(CASE WHEN mf.size > 0 THEN FILEPROPERTY(mf.name, 'SpaceUsed') * 100.0 / mf.size ELSE 0 END AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</td>'
          END
        + N'</tr>' + @crlf
    FROM sys.master_files mf
    JOIN sys.databases d ON mf.database_id = d.database_id
    LEFT JOIN sys.filegroups fg ON mf.data_space_id = fg.data_space_id AND mf.database_id = DB_ID()
    WHERE d.state_desc = N'ONLINE'
    ORDER BY d.name, mf.type, mf.file_id;

    IF LEN(@section) > 0
        SET @html = @html + N'<table id="filegroup_usage" border="1" width="90%" align="center">'
            + N'<tr><th>Database</th><th>FileGroup</th><th>File</th><th>Size_MB</th><th>Used_MB</th><th>Free_MB</th><th>Usage%</th></tr>'
            + @section + N'</table>' + @crlf;
    ELSE
        SET @html = @html + N'<table id="filegroup_usage" border="1" width="90%" align="center">'
            + N'<tr><th>Database</th><th>FileGroup</th><th>File</th><th>Size_MB</th><th>Used_MB</th><th>Free_MB</th><th>Usage%</th></tr>'
            + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- filegroup_usage error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="filegroup_usage" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>FileGroup</th><th>File</th><th>Size_MB</th><th>Used_MB</th><th>Free_MB</th><th>Usage%</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 2. connection_count - Current connections by database
-- Columns: Database, Login, Count, Status
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + ISNULL(DB_NAME(s.database_id), N'N/A') + N'</td>'
        + N'<td>' + ISNULL(s.login_name, N'N/A') + N'</td>'
        + N'<td>' + CAST(cnt AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + status + N'</td>'
        + N'</tr>' + @crlf
    FROM (
        SELECT database_id, login_name, status, COUNT(*) AS cnt
        FROM sys.dm_exec_sessions
        WHERE is_user_process = 1
        GROUP BY database_id, login_name, status
    ) s
    ORDER BY cnt DESC;

    SET @html = @html + N'<table id="connection_count" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Login</th><th>Count</th><th>Status</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- connection_count error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="connection_count" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Login</th><th>Count</th><th>Status</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 3. slow_query - Long running queries (> 60 seconds)
-- Columns: Session_ID, Duration_Sec, Status, Command, Query
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + CAST(r.session_id AS NVARCHAR(10)) + N'</td>'
        + CASE
            WHEN DATEDIFF(SECOND, r.start_time, GETDATE()) > 300
            THEN N'<td><font color="red"><b>' + CAST(DATEDIFF(SECOND, r.start_time, GETDATE()) AS NVARCHAR(20)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(DATEDIFF(SECOND, r.start_time, GETDATE()) AS NVARCHAR(20)) + N'</td>'
          END
        + N'<td>' + r.status + N'</td>'
        + N'<td>' + r.command + N'</td>'
        + N'<td>' + LEFT(ISNULL(CAST(t.text AS NVARCHAR(MAX)), N''), 200) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.session_id > 50
      AND DATEDIFF(SECOND, r.start_time, GETDATE()) > 60
    ORDER BY DATEDIFF(SECOND, r.start_time, GETDATE()) DESC;

    SET @html = @html + N'<table id="slow_query" border="1" width="90%" align="center">'
        + N'<tr><th>Session_ID</th><th>Duration_Sec</th><th>Status</th><th>Command</th><th>Query</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- slow_query error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="slow_query" border="1" width="90%" align="center">'
        + N'<tr><th>Session_ID</th><th>Duration_Sec</th><th>Status</th><th>Command</th><th>Query</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 4. agent_jobs - SQL Agent job status
-- Columns: Job_Name, Enabled, Last_Run_Status, Last_Run_Date, Schedule
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + j.name + N'</td>'
        + N'<td>' + CASE j.enabled WHEN 1 THEN N'Yes' ELSE N'No' END + N'</td>'
        + CASE
            WHEN h.run_status = 0
            THEN N'<td><font color="red"><b>Failed</b></font></td>'
            WHEN h.run_status = 1 THEN N'<td>Succeeded</td>'
            WHEN h.run_status = 2 THEN N'<td>Retry</td>'
            WHEN h.run_status = 3 THEN N'<td>Canceled</td>'
            ELSE N'<td>N/A</td>'
          END
        + N'<td>' + ISNULL(
            STUFF(STUFF(CAST(h.run_date AS NVARCHAR(8)), 5, 0, '-'), 8, 0, '-')
            + ' '
            + STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS NVARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':'),
            N'Never')
          + N'</td>'
        + N'<td>' + ISNULL(sc.name, N'No Schedule') + N'</td>'
        + N'</tr>' + @crlf
    FROM msdb.dbo.sysjobs j
    OUTER APPLY (
        SELECT TOP 1 run_status, run_date, run_time
        FROM msdb.dbo.sysjobhistory
        WHERE job_id = j.job_id AND step_id = 0
        ORDER BY run_date DESC, run_time DESC
    ) h
    LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
    LEFT JOIN msdb.dbo.sysschedules sc ON js.schedule_id = sc.schedule_id
    ORDER BY j.name;

    SET @html = @html + N'<table id="agent_jobs" border="1" width="90%" align="center">'
        + N'<tr><th>Job_Name</th><th>Enabled</th><th>Last_Run_Status</th><th>Last_Run_Date</th><th>Schedule</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- agent_jobs error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="agent_jobs" border="1" width="90%" align="center">'
        + N'<tr><th>Job_Name</th><th>Enabled</th><th>Last_Run_Status</th><th>Last_Run_Date</th><th>Schedule</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 5. always_on - AlwaysOn AG status
-- Columns: AG_Name, Replica, Role, Sync_State, Health
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    IF SERVERPROPERTY('IsHadrEnabled') = 1
    BEGIN
        SELECT @section = @section
            + N'<tr>'
            + N'<td>' + ag.name + N'</td>'
            + N'<td>' + ar.replica_server_name + N'</td>'
            + N'<td>' + ISNULL(ars.role_desc, N'UNKNOWN') + N'</td>'
            + CASE
                WHEN drs.synchronization_state_desc NOT IN (N'SYNCHRONIZING', N'SYNCHRONIZED')
                THEN N'<td><font color="red"><b>' + ISNULL(drs.synchronization_state_desc, N'N/A') + N'</b></font></td>'
                ELSE N'<td>' + ISNULL(drs.synchronization_state_desc, N'N/A') + N'</td>'
              END
            + CASE
                WHEN ISNULL(ars.synchronization_health_desc, N'') <> N'HEALTHY'
                THEN N'<td><font color="red"><b>' + ISNULL(ars.synchronization_health_desc, N'N/A') + N'</b></font></td>'
                ELSE N'<td>' + ISNULL(ars.synchronization_health_desc, N'N/A') + N'</td>'
              END
            + N'</tr>' + @crlf
        FROM sys.availability_groups ag
        JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
        LEFT JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
        LEFT JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
        ORDER BY ag.name, ar.replica_server_name;
    END

    SET @html = @html + N'<table id="always_on" border="1" width="90%" align="center">'
        + N'<tr><th>AG_Name</th><th>Replica</th><th>Role</th><th>Sync_State</th><th>Health</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- always_on error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="always_on" border="1" width="90%" align="center">'
        + N'<tr><th>AG_Name</th><th>Replica</th><th>Role</th><th>Sync_State</th><th>Health</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 6. transaction_log - Transaction log usage
-- Columns: Database, Log_Size_MB, Used_MB, Usage%, Status
-- ============================================================================
BEGIN TRY
    SET @section = N'';

    DECLARE @log_space TABLE (
        database_name NVARCHAR(256),
        database_id INT,
        log_size_mb DECIMAL(18,2),
        used_mb DECIMAL(18,2),
        used_pct DECIMAL(5,2),
        log_status INT
    );

    INSERT INTO @log_space (database_name, database_id, log_size_mb, used_mb, used_pct, log_status)
    SELECT
        d.name,
        d.database_id,
        CAST(ls.total_log_size_in_bytes / 1048576.0 AS DECIMAL(18,2)),
        CAST(ls.used_log_space_in_bytes / 1048576.0 AS DECIMAL(18,2)),
        CAST(ls.used_log_space_in_percent AS DECIMAL(5,2)),
        0
    FROM sys.databases d
    CROSS APPLY sys.dm_db_log_space_usage ls
    WHERE d.database_id = DB_ID() AND d.state_desc = N'ONLINE';

    -- For other databases, use sys.master_files estimate
    INSERT INTO @log_space (database_name, database_id, log_size_mb, used_mb, used_pct, log_status)
    SELECT
        d.name,
        d.database_id,
        CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)),
        0,
        0,
        0
    FROM sys.databases d
    JOIN sys.master_files mf ON d.database_id = mf.database_id AND mf.type_desc = N'LOG'
    WHERE d.state_desc = N'ONLINE'
      AND d.database_id <> DB_ID()
    GROUP BY d.name, d.database_id;

    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + ls.database_name + N'</td>'
        + N'<td>' + CAST(ls.log_size_mb AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(ls.used_mb AS NVARCHAR(30)) + N'</td>'
        + CASE
            WHEN ls.used_pct >= 80
            THEN N'<td><font color="red"><b>' + CAST(ls.used_pct AS NVARCHAR(10)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(ls.used_pct AS NVARCHAR(10)) + N'</td>'
          END
        + N'<td>' + CASE WHEN d.log_reuse_wait_desc IS NOT NULL THEN d.log_reuse_wait_desc ELSE N'N/A' END + N'</td>'
        + N'</tr>' + @crlf
    FROM @log_space ls
    JOIN sys.databases d ON ls.database_id = d.database_id
    ORDER BY ls.database_name;

    SET @html = @html + N'<table id="transaction_log" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Log_Size_MB</th><th>Used_MB</th><th>Usage%</th><th>Status</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- transaction_log error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="transaction_log" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Log_Size_MB</th><th>Used_MB</th><th>Usage%</th><th>Status</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 7. index_fragmentation - Index fragmentation (current database, top 50)
-- Columns: Database, Schema, Table, Index, Fragmentation%, Pages, Recommendation
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 50 @section = @section
        + N'<tr>'
        + N'<td>' + DB_NAME() + N'</td>'
        + N'<td>' + s.name + N'</td>'
        + N'<td>' + o.name + N'</td>'
        + N'<td>' + ISNULL(i.name, N'HEAP') + N'</td>'
        + CASE
            WHEN ips.avg_fragmentation_in_percent > 30 AND ips.page_count > 1000
            THEN N'<td><font color="red"><b>' + CAST(CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</td>'
          END
        + N'<td>' + CAST(ips.page_count AS NVARCHAR(20)) + N'</td>'
        + N'<td>' + CASE
            WHEN ips.avg_fragmentation_in_percent > 30 AND ips.page_count > 1000 THEN N'REBUILD'
            WHEN ips.avg_fragmentation_in_percent > 10 AND ips.page_count > 1000 THEN N'REORGANIZE'
            ELSE N'OK'
          END + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N'LIMITED') ips
    JOIN sys.objects o ON ips.object_id = o.object_id
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    LEFT JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.page_count > 100
      AND o.is_ms_shipped = 0
      AND ips.index_id > 0
    ORDER BY ips.avg_fragmentation_in_percent DESC;

    SET @html = @html + N'<table id="index_fragmentation" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Schema</th><th>Table</th><th>Index</th><th>Fragmentation%</th><th>Pages</th><th>Recommendation</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- index_fragmentation error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="index_fragmentation" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Schema</th><th>Table</th><th>Index</th><th>Fragmentation%</th><th>Pages</th><th>Recommendation</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 8. wait_stats - Top wait statistics
-- Columns: Wait_Type, Wait_Time_Sec, Pct, Running_Pct
-- ============================================================================
BEGIN TRY
    SET @section = N'';

    ;WITH waits AS (
        SELECT
            wait_type,
            wait_time_ms / 1000.0 AS wait_time_sec,
            100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER(), 0) AS pct,
            ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS rn
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            N'SLEEP_TASK', N'BROKER_TASK_STOP', N'BROKER_IO_FLUSH',
            N'SQLTRACE_BUFFER_FLUSH', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT',
            N'LAZYWRITER_SLEEP', N'CHECKPOINT_QUEUE', N'WAITFOR',
            N'XE_TIMER_EVENT', N'XE_DISPATCH_QUEUE', N'FT_IFTS_SCHEDULER_IDLE_WAIT',
            N'LOGMGR_QUEUE', N'DIRTY_PAGE_POLL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
            N'SP_SERVER_DIAGNOSTICS_SLEEP', N'BROKER_EVENTHANDLER',
            N'BROKER_RECEIVE_WAITFOR', N'BROKER_TRANSMITTER',
            N'REQUEST_FOR_DEADLOCK_SEARCH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            N'ONDEMAND_TASK_QUEUE', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            N'PREEMPTIVE_OS_AUTHORIZATIONOPS', N'PREEMPTIVE_OS_GETPROCADDRESS'
        )
          AND wait_time_ms > 0
    )
    SELECT @section = @section
        + N'<tr>'
        + CASE
            WHEN w.wait_type IN (N'CXPACKET', N'CXCONSUMER', N'PAGEIOLATCH_SH', N'PAGEIOLATCH_EX',
                N'LCK_M_S', N'LCK_M_X', N'LCK_M_U', N'LCK_M_IX', N'LCK_M_IS',
                N'WRITELOG', N'IO_COMPLETION', N'ASYNC_NETWORK_IO')
            THEN N'<td><font color="red"><b>' + w.wait_type + N'</b></font></td>'
            ELSE N'<td>' + w.wait_type + N'</td>'
          END
        + N'<td>' + CAST(CAST(w.wait_time_sec AS DECIMAL(18,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST(w.pct AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST(CAST(SUM(w2.pct) AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</td>'
        + N'</tr>' + @crlf
    FROM waits w
    JOIN waits w2 ON w2.rn <= w.rn
    WHERE w.rn <= 20
    GROUP BY w.rn, w.wait_type, w.wait_time_sec, w.pct
    ORDER BY w.rn;

    SET @html = @html + N'<table id="wait_stats" border="1" width="90%" align="center">'
        + N'<tr><th>Wait_Type</th><th>Wait_Time_Sec</th><th>Pct</th><th>Running_Pct</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- wait_stats error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="wait_stats" border="1" width="90%" align="center">'
        + N'<tr><th>Wait_Type</th><th>Wait_Time_Sec</th><th>Pct</th><th>Running_Pct</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 9. backup_status - Backup history (last 7 days)
-- Columns: Database, Type, Status, Start_Time, Duration_Sec, Size_MB
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + bs.database_name + N'</td>'
        + N'<td>' + CASE bs.type
            WHEN 'D' THEN N'Full'
            WHEN 'I' THEN N'Differential'
            WHEN 'L' THEN N'Log'
            ELSE bs.type
          END + N'</td>'
        + N'<td>' + CASE
            WHEN bmf.physical_device_name IS NOT NULL THEN N'Completed'
            ELSE N'<font color="red"><b>Unknown</b></font>'
          END + N'</td>'
        + N'<td>' + CONVERT(NVARCHAR(20), bs.backup_start_date, 120) + N'</td>'
        + N'<td>' + CAST(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS NVARCHAR(20)) + N'</td>'
        + N'<td>' + CAST(CAST(bs.backup_size / 1048576.0 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'</tr>' + @crlf
    FROM msdb.dbo.backupset bs
    LEFT JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
    WHERE bs.backup_start_date >= DATEADD(DAY, -7, GETDATE())
    ORDER BY bs.backup_start_date DESC;

    -- Check for databases without recent full backup
    DECLARE @no_backup_section NVARCHAR(MAX) = N'';
    SELECT @no_backup_section = @no_backup_section
        + N'<tr>'
        + N'<td>' + d.name + N'</td>'
        + N'<td>Full</td>'
        + N'<td><font color="red"><b>No Backup in 7 Days</b></font></td>'
        + N'<td>N/A</td>'
        + N'<td>N/A</td>'
        + N'<td>N/A</td>'
        + N'</tr>' + @crlf
    FROM sys.databases d
    WHERE d.database_id > 4  -- exclude system databases
      AND d.state_desc = N'ONLINE'
      AND NOT EXISTS (
          SELECT 1 FROM msdb.dbo.backupset bs
          WHERE bs.database_name = d.name
            AND bs.type = 'D'
            AND bs.backup_start_date >= DATEADD(DAY, -7, GETDATE())
      );

    SET @html = @html + N'<table id="backup_status" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Type</th><th>Status</th><th>Start_Time</th><th>Duration_Sec</th><th>Size_MB</th></tr>'
        + @section + @no_backup_section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- backup_status error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="backup_status" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Type</th><th>Status</th><th>Start_Time</th><th>Duration_Sec</th><th>Size_MB</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 10. security_audit - Security settings
-- Columns: Setting, Value, Recommendation
-- ============================================================================
BEGIN TRY
    SET @section = N'';

    -- Check sa account
    DECLARE @sa_enabled INT = 0;
    SELECT @sa_enabled = CASE WHEN is_disabled = 0 THEN 1 ELSE 0 END
    FROM sys.server_principals WHERE sid = 0x01;

    SET @section = @section + N'<tr>'
        + CASE WHEN @sa_enabled = 1
            THEN N'<td>sa Account</td><td><font color="red"><b>Enabled</b></font></td><td><font color="red"><b>Disable the sa account or rename it</b></font></td>'
            ELSE N'<td>sa Account</td><td>Disabled</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    -- Check xp_cmdshell
    DECLARE @xp_cmdshell INT = 0;
    SELECT @xp_cmdshell = CAST(value_in_use AS INT)
    FROM sys.configurations WHERE name = N'xp_cmdshell';

    SET @section = @section + N'<tr>'
        + CASE WHEN @xp_cmdshell = 1
            THEN N'<td>xp_cmdshell</td><td><font color="red"><b>Enabled</b></font></td><td><font color="red"><b>Disable xp_cmdshell for security</b></font></td>'
            ELSE N'<td>xp_cmdshell</td><td>Disabled</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    -- Check CLR
    DECLARE @clr_enabled INT = 0;
    SELECT @clr_enabled = CAST(value_in_use AS INT)
    FROM sys.configurations WHERE name = N'clr enabled';

    SET @section = @section + N'<tr>'
        + CASE WHEN @clr_enabled = 1
            THEN N'<td>CLR Enabled</td><td><font color="red"><b>Enabled</b></font></td><td><font color="red"><b>Disable CLR if not required</b></font></td>'
            ELSE N'<td>CLR Enabled</td><td>Disabled</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    -- Check remote admin connections
    DECLARE @remote_dac INT = 0;
    SELECT @remote_dac = CAST(value_in_use AS INT)
    FROM sys.configurations WHERE name = N'remote admin connections';

    SET @section = @section + N'<tr>'
        + CASE WHEN @remote_dac = 1
            THEN N'<td>Remote DAC</td><td>Enabled</td><td>Review if remote DAC is necessary</td>'
            ELSE N'<td>Remote DAC</td><td>Disabled</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    -- Check authentication mode
    DECLARE @auth_mode NVARCHAR(50);
    SELECT @auth_mode = CASE SERVERPROPERTY('IsIntegratedSecurityOnly')
        WHEN 1 THEN N'Windows Only'
        ELSE N'Mixed Mode'
    END;

    SET @section = @section + N'<tr>'
        + CASE WHEN @auth_mode = N'Mixed Mode'
            THEN N'<td>Authentication Mode</td><td><font color="red"><b>Mixed Mode</b></font></td><td>Consider Windows Authentication only</td>'
            ELSE N'<td>Authentication Mode</td><td>Windows Only</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    -- Check cross db ownership chaining
    DECLARE @cross_db INT = 0;
    SELECT @cross_db = CAST(value_in_use AS INT)
    FROM sys.configurations WHERE name = N'cross db ownership chaining';

    SET @section = @section + N'<tr>'
        + CASE WHEN @cross_db = 1
            THEN N'<td>Cross DB Ownership Chaining</td><td><font color="red"><b>Enabled</b></font></td><td><font color="red"><b>Disable unless specifically required</b></font></td>'
            ELSE N'<td>Cross DB Ownership Chaining</td><td>Disabled</td><td>OK</td>'
          END
        + N'</tr>' + @crlf;

    SET @html = @html + N'<table id="security_audit" border="1" width="90%" align="center">'
        + N'<tr><th>Setting</th><th>Value</th><th>Recommendation</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- security_audit error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="security_audit" border="1" width="90%" align="center">'
        + N'<tr><th>Setting</th><th>Value</th><th>Recommendation</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 11. server_config - Key server configuration settings
-- Columns: Name, Value, Value_In_Use, Min, Max, Is_Dynamic
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + c.name + N'</td>'
        + N'<td>' + CAST(c.value AS NVARCHAR(30)) + N'</td>'
        + CASE
            WHEN c.name = N'max server memory (MB)' AND CAST(c.value_in_use AS BIGINT) = 2147483647
            THEN N'<td><font color="red"><b>' + CAST(c.value_in_use AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(c.value_in_use AS NVARCHAR(30)) + N'</td>'
          END
        + N'<td>' + CAST(c.minimum AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(c.maximum AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CASE c.is_dynamic WHEN 1 THEN N'Yes' ELSE N'No' END + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.configurations c
    WHERE c.name IN (
        N'max server memory (MB)',
        N'min server memory (MB)',
        N'max degree of parallelism',
        N'cost threshold for parallelism',
        N'optimize for ad hoc workloads',
        N'max worker threads'
    )
    ORDER BY c.name;

    SET @html = @html + N'<table id="server_config" border="1" width="90%" align="center">'
        + N'<tr><th>Name</th><th>Value</th><th>Value_In_Use</th><th>Min</th><th>Max</th><th>Is_Dynamic</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- server_config error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="server_config" border="1" width="90%" align="center">'
        + N'<tr><th>Name</th><th>Value</th><th>Value_In_Use</th><th>Min</th><th>Max</th><th>Is_Dynamic</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 12. database_info - All databases summary
-- Columns: Database, State, Recovery_Model, Compatibility, Size_MB, Owner, Created
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + d.name + N'</td>'
        + N'<td>' + d.state_desc + N'</td>'
        + CASE
            WHEN d.recovery_model_desc = N'SIMPLE' AND d.database_id > 4
            THEN N'<td><font color="red"><b>' + d.recovery_model_desc + N'</b></font></td>'
            ELSE N'<td>' + d.recovery_model_desc + N'</td>'
          END
        + N'<td>' + CAST(d.compatibility_level AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST(CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + ISNULL(SUSER_SNAME(d.owner_sid), N'N/A') + N'</td>'
        + N'<td>' + CONVERT(NVARCHAR(20), d.create_date, 120) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.databases d
    JOIN sys.master_files mf ON d.database_id = mf.database_id
    GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level,
             d.owner_sid, d.create_date, d.database_id
    ORDER BY d.name;

    SET @html = @html + N'<table id="database_info" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>State</th><th>Recovery_Model</th><th>Compatibility</th><th>Size_MB</th><th>Owner</th><th>Created</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- database_info error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="database_info" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>State</th><th>Recovery_Model</th><th>Compatibility</th><th>Size_MB</th><th>Owner</th><th>Created</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 13. disk_space - Database file I/O stats
-- Columns: Database, File, Type, Size_MB, Reads, Writes, Read_Latency_ms, Write_Latency_ms
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + DB_NAME(vfs.database_id) + N'</td>'
        + N'<td>' + mf.physical_name + N'</td>'
        + N'<td>' + mf.type_desc + N'</td>'
        + N'<td>' + CAST(CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(vfs.num_of_reads AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(vfs.num_of_writes AS NVARCHAR(30)) + N'</td>'
        + CASE
            WHEN vfs.num_of_reads > 0 AND (vfs.io_stall_read_ms / vfs.num_of_reads) > 50
            THEN N'<td><font color="red"><b>' + CAST(CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CASE WHEN vfs.num_of_reads > 0 THEN CAST(vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads AS DECIMAL(12,2)) ELSE 0 END AS NVARCHAR(30)) + N'</td>'
          END
        + CASE
            WHEN vfs.num_of_writes > 0 AND (vfs.io_stall_write_ms / vfs.num_of_writes) > 50
            THEN N'<td><font color="red"><b>' + CAST(CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CASE WHEN vfs.num_of_writes > 0 THEN CAST(vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes AS DECIMAL(12,2)) ELSE 0 END AS NVARCHAR(30)) + N'</td>'
          END
        + N'</tr>' + @crlf
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    ORDER BY vfs.io_stall DESC;

    SET @html = @html + N'<table id="disk_space" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>File</th><th>Type</th><th>Size_MB</th><th>Reads</th><th>Writes</th><th>Read_Latency_ms</th><th>Write_Latency_ms</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- disk_space error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="disk_space" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>File</th><th>Type</th><th>Size_MB</th><th>Reads</th><th>Writes</th><th>Read_Latency_ms</th><th>Write_Latency_ms</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 14. tempdb_usage - TempDB usage
-- Columns: File, Size_MB, Used_MB, Free_MB, Usage_Pct
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + mf.name + N'</td>'
        + N'<td>' + CAST(CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST(dsu.unallocated_extent_page_count * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST((mf.size * 8.0 / 1024) - (dsu.unallocated_extent_page_count * 8.0 / 1024) AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + CASE
            WHEN mf.size > 0 AND ((mf.size - dsu.unallocated_extent_page_count) * 100.0 / mf.size) > 80
            THEN N'<td><font color="red"><b>' + CAST(CAST((mf.size - dsu.unallocated_extent_page_count) * 100.0 / mf.size AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CAST(CASE WHEN mf.size > 0 THEN (mf.size - dsu.unallocated_extent_page_count) * 100.0 / mf.size ELSE 0 END AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'</td>'
          END
        + N'</tr>' + @crlf
    FROM tempdb.sys.database_files mf
    JOIN sys.dm_db_file_space_usage dsu ON mf.file_id = dsu.file_id
    WHERE mf.type_desc = N'ROWS'
    ORDER BY mf.file_id;

    SET @html = @html + N'<table id="tempdb_usage" border="1" width="90%" align="center">'
        + N'<tr><th>File</th><th>Size_MB</th><th>Used_MB</th><th>Free_MB</th><th>Usage_Pct</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- tempdb_usage error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="tempdb_usage" border="1" width="90%" align="center">'
        + N'<tr><th>File</th><th>Size_MB</th><th>Used_MB</th><th>Free_MB</th><th>Usage_Pct</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 15. object_count - Object counts (current database)
-- Columns: Database, Tables, Views, Procedures, Functions, Indexes
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + DB_NAME() + N'</td>'
        + N'<td>' + CAST(SUM(CASE WHEN o.type = 'U' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST(SUM(CASE WHEN o.type = 'V' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST(SUM(CASE WHEN o.type = 'P' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST(SUM(CASE WHEN o.type IN ('FN','IF','TF','AF') THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>'
        + N'<td>' + CAST((SELECT COUNT(*) FROM sys.indexes WHERE object_id IN (SELECT object_id FROM sys.objects WHERE is_ms_shipped = 0) AND index_id > 0) AS NVARCHAR(10)) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.objects o
    WHERE o.is_ms_shipped = 0
      AND o.type IN ('U','V','P','FN','IF','TF','AF');

    SET @html = @html + N'<table id="object_count" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Tables</th><th>Views</th><th>Procedures</th><th>Functions</th><th>Indexes</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- object_count error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="object_count" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Tables</th><th>Views</th><th>Procedures</th><th>Functions</th><th>Indexes</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 16. blocking_sessions - Current blocking chains
-- Columns: Blocked_SPID, Blocked_Query, Blocking_SPID, Blocking_Query, Wait_Type, Wait_Time_Sec
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 50 @section = @section
        + N'<tr>'
        + N'<td><font color="red"><b>' + CAST(blocked.session_id AS NVARCHAR(10)) + N'</b></font></td>'
        + N'<td><font color="red"><b>' + LEFT(ISNULL(CAST(bt.text AS NVARCHAR(MAX)), N''), 200) + N'</b></font></td>'
        + N'<td><font color="red"><b>' + CAST(blocked.blocking_session_id AS NVARCHAR(10)) + N'</b></font></td>'
        + N'<td><font color="red"><b>' + LEFT(ISNULL(CAST(blt.text AS NVARCHAR(MAX)), N''), 200) + N'</b></font></td>'
        + N'<td><font color="red"><b>' + ISNULL(blocked.wait_type, N'N/A') + N'</b></font></td>'
        + N'<td><font color="red"><b>' + CAST(CAST(blocked.wait_time / 1000.0 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</b></font></td>'
        + N'</tr>' + @crlf
    FROM sys.dm_exec_requests blocked
    CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) bt
    LEFT JOIN sys.dm_exec_requests blocker ON blocked.blocking_session_id = blocker.session_id
    OUTER APPLY sys.dm_exec_sql_text(blocker.sql_handle) blt
    WHERE blocked.blocking_session_id > 0
    ORDER BY blocked.wait_time DESC;

    SET @html = @html + N'<table id="blocking_sessions" border="1" width="90%" align="center">'
        + N'<tr><th>Blocked_SPID</th><th>Blocked_Query</th><th>Blocking_SPID</th><th>Blocking_Query</th><th>Wait_Type</th><th>Wait_Time_Sec</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- blocking_sessions error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="blocking_sessions" border="1" width="90%" align="center">'
        + N'<tr><th>Blocked_SPID</th><th>Blocked_Query</th><th>Blocking_SPID</th><th>Blocking_Query</th><th>Wait_Type</th><th>Wait_Time_Sec</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 17. top_queries_by_cpu - Top CPU-consuming queries from plan cache
-- Columns: CPU_Time_ms, Exec_Count, Avg_CPU_ms, Total_Reads, Query_Text
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 20 @section = @section
        + N'<tr>'
        + N'<td>' + CAST(qs.total_worker_time / 1000 AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(qs.execution_count AS NVARCHAR(20)) + N'</td>'
        + CASE
            WHEN (qs.total_worker_time / 1000) / NULLIF(qs.execution_count, 0) > 10000
            THEN N'<td><font color="red"><b>' + CAST((qs.total_worker_time / 1000) / NULLIF(qs.execution_count, 0) AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(ISNULL((qs.total_worker_time / 1000) / NULLIF(qs.execution_count, 0), 0) AS NVARCHAR(30)) + N'</td>'
          END
        + N'<td>' + CAST(qs.total_logical_reads AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + LEFT(ISNULL(CAST(t.text AS NVARCHAR(MAX)), N''), 300) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
    ORDER BY qs.total_worker_time DESC;

    SET @html = @html + N'<table id="top_queries_by_cpu" border="1" width="90%" align="center">'
        + N'<tr><th>CPU_Time_ms</th><th>Exec_Count</th><th>Avg_CPU_ms</th><th>Total_Reads</th><th>Query_Text</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- top_queries_by_cpu error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="top_queries_by_cpu" border="1" width="90%" align="center">'
        + N'<tr><th>CPU_Time_ms</th><th>Exec_Count</th><th>Avg_CPU_ms</th><th>Total_Reads</th><th>Query_Text</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 18. missing_indexes - Missing index suggestions
-- Columns: Database, Table, Equality_Columns, Inequality_Columns, Include_Columns, Impact, User_Seeks
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 20 @section = @section
        + N'<tr>'
        + N'<td>' + ISNULL(DB_NAME(mid.database_id), N'N/A') + N'</td>'
        + N'<td>' + ISNULL(mid.statement, N'N/A') + N'</td>'
        + N'<td>' + ISNULL(mid.equality_columns, N'') + N'</td>'
        + N'<td>' + ISNULL(mid.inequality_columns, N'') + N'</td>'
        + N'<td>' + ISNULL(mid.included_columns, N'') + N'</td>'
        + CASE
            WHEN CAST(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) > 100000
            THEN N'<td><font color="red"><b>' + CAST(CAST(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CAST(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS DECIMAL(18,2)) AS NVARCHAR(30)) + N'</td>'
          END
        + N'<td>' + CAST(migs.user_seeks AS NVARCHAR(20)) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.dm_db_missing_index_details mid
    JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
    JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
    ORDER BY migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC;

    SET @html = @html + N'<table id="missing_indexes" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Table</th><th>Equality_Columns</th><th>Inequality_Columns</th><th>Include_Columns</th><th>Impact</th><th>User_Seeks</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- missing_indexes error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="missing_indexes" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>Table</th><th>Equality_Columns</th><th>Inequality_Columns</th><th>Include_Columns</th><th>Impact</th><th>User_Seeks</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 19. table_no_pk - Tables without primary key (current database)
-- Columns: Schema, Table, Rows, Size_MB
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 50 @section = @section
        + N'<tr>'
        + N'<td><font color="red"><b>' + s.name + N'</b></font></td>'
        + N'<td><font color="red"><b>' + t.name + N'</b></font></td>'
        + N'<td><font color="red"><b>' + CAST(ISNULL(p.row_cnt, 0) AS NVARCHAR(20)) + N'</b></font></td>'
        + N'<td><font color="red"><b>' + CAST(CAST(ISNULL(p.total_pages * 8.0 / 1024, 0) AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</b></font></td>'
        + N'</tr>' + @crlf
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    LEFT JOIN (
        SELECT object_id, SUM(rows) AS row_cnt, SUM(total_pages) AS total_pages
        FROM sys.partitions p2
        JOIN sys.allocation_units au ON p2.partition_id = au.container_id
        WHERE p2.index_id IN (0, 1)
        GROUP BY object_id
    ) p ON t.object_id = p.object_id
    WHERE t.is_ms_shipped = 0
      AND NOT EXISTS (
          SELECT 1 FROM sys.indexes i
          WHERE i.object_id = t.object_id AND i.is_primary_key = 1
      )
    ORDER BY ISNULL(p.row_cnt, 0) DESC;

    SET @html = @html + N'<table id="table_no_pk" border="1" width="90%" align="center">'
        + N'<tr><th>Schema</th><th>Table</th><th>Rows</th><th>Size_MB</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- table_no_pk error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="table_no_pk" border="1" width="90%" align="center">'
        + N'<tr><th>Schema</th><th>Table</th><th>Rows</th><th>Size_MB</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 20. top_tables_by_size - Largest tables (current database)
-- Columns: Schema, Table, Rows, Total_Size_MB, Data_MB, Index_MB
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT TOP 20 @section = @section
        + N'<tr>'
        + N'<td>' + s.name + N'</td>'
        + N'<td>' + t.name + N'</td>'
        + N'<td>' + CAST(p.row_cnt AS NVARCHAR(20)) + N'</td>'
        + CASE
            WHEN (p.total_pages * 8.0 / 1024) > 10240
            THEN N'<td><font color="red"><b>' + CAST(CAST(p.total_pages * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</b></font></td>'
            ELSE N'<td>' + CAST(CAST(p.total_pages * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
          END
        + N'<td>' + CAST(CAST(p.data_pages * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'<td>' + CAST(CAST((p.total_pages - p.data_pages) * 8.0 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(30)) + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    JOIN (
        SELECT object_id,
               SUM(rows) AS row_cnt,
               SUM(total_pages) AS total_pages,
               SUM(CASE WHEN au.type = 1 THEN au.total_pages ELSE 0 END) AS data_pages
        FROM sys.partitions p2
        JOIN sys.allocation_units au ON p2.partition_id = au.container_id
        WHERE p2.index_id IN (0, 1)
        GROUP BY object_id
    ) p ON t.object_id = p.object_id
    WHERE t.is_ms_shipped = 0
    ORDER BY p.total_pages DESC;

    SET @html = @html + N'<table id="top_tables_by_size" border="1" width="90%" align="center">'
        + N'<tr><th>Schema</th><th>Table</th><th>Rows</th><th>Total_Size_MB</th><th>Data_MB</th><th>Index_MB</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- top_tables_by_size error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="top_tables_by_size" border="1" width="90%" align="center">'
        + N'<tr><th>Schema</th><th>Table</th><th>Rows</th><th>Total_Size_MB</th><th>Data_MB</th><th>Index_MB</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 21. error_log_recent - Recent SQL Server error log entries
-- Columns: LogDate, ProcessInfo, Text
-- ============================================================================
BEGIN TRY
    SET @section = N'';

    DECLARE @error_log TABLE (
        LogDate DATETIME,
        ProcessInfo NVARCHAR(256),
        LogText NVARCHAR(MAX)
    );

    INSERT INTO @error_log (LogDate, ProcessInfo, LogText)
    EXEC xp_readerrorlog 0, 1, N'Error', NULL, NULL, NULL, N'DESC';

    INSERT INTO @error_log (LogDate, ProcessInfo, LogText)
    EXEC xp_readerrorlog 0, 1, N'Severity', NULL, NULL, NULL, N'DESC';

    SELECT TOP 50 @section = @section
        + N'<tr>'
        + N'<td>' + CONVERT(NVARCHAR(20), el.LogDate, 120) + N'</td>'
        + N'<td>' + ISNULL(el.ProcessInfo, N'') + N'</td>'
        + CASE
            WHEN el.LogText LIKE N'%Severity: [1-2][0-9]%' OR el.LogText LIKE N'%Error:%'
            THEN N'<td><font color="red"><b>' + LEFT(ISNULL(el.LogText, N''), 300) + N'</b></font></td>'
            ELSE N'<td>' + LEFT(ISNULL(el.LogText, N''), 300) + N'</td>'
          END
        + N'</tr>' + @crlf
    FROM @error_log el
    ORDER BY el.LogDate DESC;

    SET @html = @html + N'<table id="error_log_recent" border="1" width="90%" align="center">'
        + N'<tr><th>LogDate</th><th>ProcessInfo</th><th>Text</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- error_log_recent error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="error_log_recent" border="1" width="90%" align="center">'
        + N'<tr><th>LogDate</th><th>ProcessInfo</th><th>Text</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- 22. database_users - Database users and roles (current database)
-- Columns: Database, User, Type, Default_Schema, Roles
-- ============================================================================
BEGIN TRY
    SET @section = N'';
    SELECT @section = @section
        + N'<tr>'
        + N'<td>' + DB_NAME() + N'</td>'
        + N'<td>' + dp.name + N'</td>'
        + N'<td>' + dp.type_desc + N'</td>'
        + N'<td>' + ISNULL(dp.default_schema_name, N'') + N'</td>'
        + N'<td>' + ISNULL(STUFF((
            SELECT N', ' + r.name
            FROM sys.database_role_members drm
            JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
            WHERE drm.member_principal_id = dp.principal_id
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, N''), N'') + N'</td>'
        + N'</tr>' + @crlf
    FROM sys.database_principals dp
    WHERE dp.type IN ('S', 'U', 'G', 'E', 'X')
      AND dp.name NOT IN (N'sys', N'INFORMATION_SCHEMA', N'guest', N'public')
      AND dp.name NOT LIKE N'##%'
    ORDER BY dp.name;

    SET @html = @html + N'<table id="database_users" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>User</th><th>Type</th><th>Default_Schema</th><th>Roles</th></tr>'
        + @section + N'</table>' + @crlf;
END TRY
BEGIN CATCH
    SET @html = @html + N'<!-- database_users error: ' + ERROR_MESSAGE() + N' -->' + @crlf
        + N'<table id="database_users" border="1" width="90%" align="center">'
        + N'<tr><th>Database</th><th>User</th><th>Type</th><th>Default_Schema</th><th>Roles</th></tr>'
        + N'</table>' + @crlf;
END CATCH

-- ============================================================================
-- HTML Footer
-- ============================================================================
SET @html = @html + N'<hr><center><font size="-1">Generated by DBCheck SQL Server Script</font></center>' + @crlf
    + N'</body></html>';

-- ============================================================================
-- Output: Print HTML in chunks (PRINT has 8000 char limit for NVARCHAR)
-- ============================================================================
DECLARE @pos INT = 1;
DECLARE @len INT = LEN(@html);
DECLARE @chunk INT = 4000;

WHILE @pos <= @len
BEGIN
    PRINT SUBSTRING(@html, @pos, @chunk);
    SET @pos = @pos + @chunk;
END
GO
