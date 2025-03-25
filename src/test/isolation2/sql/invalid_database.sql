-- test that interruption of DROP DATABASE is handled properly

!\retcode gpconfig -c autovacuum -v off;
!\retcode gpstop -au;

-- start_ignore
DROP DATABASE IF EXISTS regression_invalid_interrupt;
-- end_ignore
CREATE DATABASE regression_invalid_interrupt;

-- prevent drop database via suspend in inject fault on segment 0
SELECT gp_inject_fault('dropdb_before_remove_tablespace', 'suspend', dbid)
FROM gp_segment_configuration WHERE content = 0 AND role = 'p';

-- try to drop, this will wait due to the suspend on segment 0
1&: DROP DATABASE regression_invalid_interrupt;

-- ensure we're suspending in inject fault on segment 0
SELECT gp_wait_until_triggered_fault('dropdb_before_remove_tablespace', 1, dbid)
FROM gp_segment_configuration WHERE content = 0 AND role = 'p';

-- and finally interrupt the DROP DATABASE on segment 0
0U: SELECT pg_cancel_backend(pid) FROM pg_stat_activity
WHERE query = 'DROP DATABASE IF EXISTS regression_invalid_interrupt';
0Uq:

1<:
1q:

-- verify that connection to the database aren't allowed
! psql -d regression_invalid_interrupt -c "SELECT 1";

-- to properly drop the database, we need to reset inject fault
SELECT gp_inject_fault('dropdb_before_remove_tablespace', 'reset', dbid)
FROM gp_segment_configuration WHERE content = 0 AND role = 'p';

DROP DATABASE regression_invalid_interrupt;

!\retcode gpconfig -r autovacuum;
!\retcode gpstop -au;
