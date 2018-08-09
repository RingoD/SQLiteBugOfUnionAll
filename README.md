This repo show a bug of SQLite.

tldr: `UNION ALL` will not merge the data in different schemas in the moment that one of schema is committed but the another not. BUT, `UNION` will.

Here are the reproduce steps:

Preparation:
1. Prepare a database named "OLD"
1.1 Create a table for "OLD": `CREATE TABLE old(i INTEGER)`
1.2 Insert values into "OLD" to make it large enough: `INSERT INTO old VALUES(?1)`
2. Prepare a database named "NEW"
2.1 Create a table for "NEW": `CREATE TABLE new(i INTEGER)`

Migration:
For thread 1:
1. Attach "OLD" to "NEW" as "oldSchema": `ATTACH OLD AS oldSchema`
2. Migrate data from "OLD" to "NEW" in same transaction. Note that they should be executed with same handle using ATTACH mentioned in 1.
	1. `BEGIN IMMEDIATE`
	2. Select one of the row from "OLD": `SELECT i FROM oldSchema.old`
	3. Insert the row into "NEW": `INSERT INTO main.new VALUES(?1)`
	4. Delete the row from "OLD": `DELETE FROM oldSchema.old WHERE i == ?1`
	5. `COMMIT`

For thread 2 to N:
1. Create a view that union two tables: `CREATE TEMP VIEW v AS SELECT i FROM oldSchema.old UNION ALL SELECT i FROM main.new`
2. Select one of the value from view: `SELECT i FROM temp.v ORDER BY i LIMIT 1 OFFSET ?1`.
Here is the strange result:
As an example, if the values of 0-999 is inserted into "OLD", then value N should be selected as expected at offset N.
But in these kind of steps, it will not.

It can be a little bit hard to reproduce due to the multi-threading. BUT if it sleeps for a while when committing, it will be much easier to reproduce:

	// vdbeCommit method of vdbeaux.c
	for(i=0; rc==SQLITE_OK && i<db->nDb; i++){
	  Btree *pBt = db->aDb[i].pBt;
	  sqlite3_sleep(10); // additional sleep here
	  if( pBt ){
	    rc = sqlite3BtreeCommitPhaseOne(pBt, 0);
	  }
	}

It seems that the bug happens when one of the schema is committed but the another one is not.
On the other handle, if `UNION ALL` is changed to `UNION` while creating view, the bug will not happen too.
