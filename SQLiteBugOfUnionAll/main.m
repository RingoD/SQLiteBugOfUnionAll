//
//  main.m
//  SQLiteBugOfUnionAll
//
//  Created by sanhuazhang on 2018/8/9.
//  Copyright © 2018 sanhuazhang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sqlcipher/sqlite3.h>
#include <assert.h>

void sqlitelog(void *userInfo, int code, const char *message)
{
    printf("SQLite: %d: %s\n", code, message);
}

sqlite3* prepareHandle(const char* path)
{
    sqlite3* handle;
    assert(sqlite3_open(path, &handle) == SQLITE_OK);
    assert(sqlite3_exec(handle, "PRAGMA main.journal_mode=WAL", NULL, NULL, NULL) == SQLITE_OK);
    assert(sqlite3_exec(handle, "PRAGMA main.synchronous=NORMAL", NULL, NULL, NULL) == SQLITE_OK);
    return handle;
}

int main()
{
    sqlite3_config(SQLITE_CONFIG_LOG, sqlitelog, NULL);
    
    NSString* nsDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SQLiteBugOfUnionAll"];
    NSString* nsOldDatabase = [nsDirectory stringByAppendingPathComponent:@"oldDatabase"];
    NSString* nsNewDatabase = [nsDirectory stringByAppendingPathComponent:@"newDatabase"];
    const char* oldDatabase = nsOldDatabase.UTF8String;
    const char* newDatabase = nsNewDatabase.UTF8String;
    int count = 100000;
    
    //Clear old data
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:nsDirectory]) {
        assert([fileManager removeItemAtPath:nsDirectory error:nil]);
    }
    assert([fileManager createDirectoryAtPath:nsDirectory withIntermediateDirectories:YES attributes:nil error:nil]);
    
    {
        // prepare old db
        sqlite3* handle = prepareHandle(oldDatabase);
        assert(sqlite3_exec(handle, "CREATE TABLE old(i INTEGER)", NULL, NULL, NULL) == SQLITE_OK);
        assert(sqlite3_exec(handle, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK);
        for (int i = 0; i < count; ++i) {
            NSString* sql = [NSString stringWithFormat:@"INSERT INTO old VALUES(%d)", i];
            assert(sqlite3_exec(handle, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK);
        }
        assert(sqlite3_exec(handle, "COMMIT", NULL, NULL, NULL) == SQLITE_OK);
        sqlite3_close(handle);
    }
    {
        //prepare new db
        
        sqlite3* handle = prepareHandle(newDatabase);
        assert(sqlite3_exec(handle, "CREATE TABLE new(i INTEGER)", NULL, NULL, NULL) == SQLITE_OK);
        sqlite3_close(handle);
    }
    
    srand((unsigned int)time(0));
    NSString* attachSQL = [NSString stringWithFormat:@"ATTACH '%s' AS oldSchema", oldDatabase];
    
    // async select repeatly
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        sqlite3* handle = prepareHandle(newDatabase);
        assert(sqlite3_exec(handle, attachSQL.UTF8String, NULL, NULL, NULL) ==  SQLITE_OK);
        
        // UNION ALL will lead to bug, but UNION will not.
        assert(sqlite3_exec(handle, "CREATE TEMP VIEW migrated AS SELECT i FROM oldSchema.old UNION ALL SELECT i FROM main.new", NULL, NULL, NULL) == SQLITE_OK);
//        assert(sqlite3_exec(handle, "CREATE TEMP VIEW migrated AS SELECT i FROM oldSchema.old UNION SELECT i FROM main.new", NULL, NULL, NULL) == SQLITE_OK);
        
        while (YES) {
            int offset = rand() % count;
            NSString* sql = [NSString stringWithFormat:@"SELECT i FROM temp.migrated ORDER BY i LIMIT 1 OFFSET %d", offset];
            sqlite3_stmt* stmt;
            assert(sqlite3_prepare_v2(handle, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK);
            assert(sqlite3_step(stmt) == SQLITE_ROW);
            int result = sqlite3_column_int(stmt, 0);
            if (result != offset) {
                NSLog(@"Strange result: offset %d but result in %d", offset, result);
                abort();
            }else {
                NSLog(@"Safe");
            }
        }
    });
    
    {
        //migration
        sqlite3* handle = prepareHandle(newDatabase);
        assert(sqlite3_exec(handle, attachSQL.UTF8String, NULL, NULL, NULL) == SQLITE_OK);
        
        for (int i = 0; i < count; ++i) {
            assert(sqlite3_exec(handle, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK);
            {
                NSString* sql = [NSString stringWithFormat:@"INSERT INTO main.new(i) SELECT i FROM oldSchema.old WHERE rowid == %d LIMIT 1", i];
                assert(sqlite3_exec(handle, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK);
            }
            {
                NSString* sql = [NSString stringWithFormat:@"DELETE FROM oldSchema.old WHERE rowid == %d LIMIT 1", i];
                assert(sqlite3_exec(handle, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK);
            }
            assert(sqlite3_exec(handle, "COMMIT", NULL, NULL, NULL) == SQLITE_OK);
        }
    }
    
    return 0;
}
