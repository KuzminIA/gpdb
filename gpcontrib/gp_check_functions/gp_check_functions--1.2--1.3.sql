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
    SELECT 1663 AS tablespace, 'base/' || d.oid::text AS dirname
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

--------------------------------------------------------------------------------
-- @view:
--        __get_expect_files
--
-- @doc:
--        Retrieve a list of expected data files in the database,
--        using the knowledge from catalogs. This does not include
--        any extended data files, nor does it include external,
--        foreign or virtual tables.
--
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW __get_expect_files AS
SELECT CASE WHEN s.reltablespace = 0 THEN
            (SELECT dattablespace FROM pg_database WHERE datname = current_database())
            ELSE s.reltablespace END AS tablespace, 
       s.relname, s.relstorage,
       (CASE WHEN s.relfilenode != 0 THEN s.relfilenode ELSE pg_relation_filenode(s.oid) END)::text AS filename
FROM pg_class s
WHERE s.relstorage NOT IN ('x', 'v', 'f');

--------------------------------------------------------------------------------
-- @view:
--        __get_expect_files_ext
--
-- @doc:
--        Retrieve a list of expected data files in the database,
--        using the knowledge from catalogs. This includes all
--        the extended data files for AO/CO tables, nor does it
--        include external, foreign or virtual tables.
--        Also ignore AO segments w/ eof=0. They might be created just for
--        modcount whereas no data has ever been inserted to the seg.
--        Or, they could be created when a seg has only aborted rows.
--        In both cases, we can ignore these segs, because no matter
--        whether the data files exist or not, the rest of the system
--        can handle them gracefully.
--
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW __get_expect_files_ext AS
WITH class_info AS (
  SELECT oid, relname, relstorage, relfilenode,
    CASE WHEN reltablespace = 0 THEN 
      (SELECT dattablespace FROM pg_database WHERE datname = current_database())
      ELSE reltablespace END AS tablespace
  FROM pg_class
)
SELECT tablespace, relname, relstorage,
       (CASE WHEN relfilenode != 0 THEN relfilenode ELSE pg_relation_filenode(oid) END)::text AS filename
FROM class_info
WHERE relstorage NOT IN ('x', 'v', 'f')
UNION
-- AO extended files
SELECT c.tablespace, c.relname, c.relstorage,
       format(c.relfilenode::text || '.' || s.segno::text) AS filename
FROM __get_ao_segno_list() s
JOIN class_info c ON s.relid = c.oid
WHERE s.eof >0 AND c.relstorage NOT IN ('x', 'v', 'f')
UNION
-- CO extended files
SELECT c.tablespace, c.relname, c.relstorage,
       format(c.relfilenode::text || '.' || s.segno::text) AS filename
FROM __get_aoco_segno_list() s
JOIN class_info c ON s.relid = c.oid
WHERE s.eof > 0 AND c.relstorage NOT IN ('x', 'v', 'f');
