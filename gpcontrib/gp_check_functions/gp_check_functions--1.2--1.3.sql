/* gpcontrib/gp_check_functions/gp_check_functions--1.2--1.3.sql */

-- complain if script is sourced in psql, rather than via ALTER EXTENSION
\echo Use "ALTER EXTENSION gp_check_functions UPDATE TO '1.3" to load this file. \quit

--------------------------------------------------------------------------------
-- @view:
--        __get_exist_files
--
-- @doc:
--        Retrieve a list of all existing data files in the default
--        and user tablespaces.
--
--------------------------------------------------------------------------------
-- return the list of existing files in the database
CREATE OR REPLACE VIEW __get_exist_files AS
WITH Tablespaces AS (
-- 1. The default tablespace
    SELECT 0 AS tablespace, 'base/' || d.oid::text AS dirname
    FROM pg_database d
    WHERE d.datname = current_database()
    UNION
-- 2. The global tablespace
    SELECT 1664 AS tablespace, 'global/' AS dirname
    UNION
-- 3. The user-defined tablespaces
    SELECT ts.oid AS tablespace,
       'pg_tblspc/' || ts.oid::text || '/' || get_tablespace_version_directory_name() || '/' ||
         (SELECT d.oid::text FROM pg_database d WHERE d.datname = current_database()) AS dirname
    FROM pg_tablespace ts
    WHERE ts.oid > 1664
)
SELECT tablespace, files.filename, dirname || '/' || files.filename AS filepath
FROM Tablespaces, pg_ls_dir(dirname, true, false) AS files(filename);
