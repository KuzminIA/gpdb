-- test that interruption of DROP DATABASE is handled properly

!\retcode gpconfig -c autovacuum -v off;
!\retcode gpstop -au;

-- start_ignore
DROP TABLE IF EXISTS store_session_id
-- end_ignore
CREATE TABLE store_session_id(a int, sess_id int);
-- adding `2` as first column as the distribution column and add this tuple to segment 0
1: INSERT INTO store_session_id SELECT 2, sess_id FROM pg_stat_activity WHERE pid = pg_backend_pid();

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
0U: SELECT pg_cancel_backend(pid) FROM pg_stat_activity JOIN store_session_id USING (sess_id)
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
