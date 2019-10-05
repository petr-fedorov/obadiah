#ifdef __cplusplus
extern "C" {
#endif // __cplusplus
#include "postgres.h"
#include "c.h"
#include "utils/timestamp.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "catalog/pg_type_d.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(spread_by_episode);

#ifdef __cplusplus
}
#endif // __cplusplus





Datum
spread_by_episode(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    TupleDesc            tupdesc;
    AttInMetadata       *attinmeta;


    if (SRF_IS_FIRSTCALL())
    {
        MemoryContext   oldcontext;

        funcctx = SRF_FIRSTCALL_INIT();

        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                            "that cannot accept type record")));
        attinmeta = TupleDescGetAttInMetadata(tupdesc);
        funcctx->attinmeta = attinmeta;

        Oid types[4];
        types[0] = TIMESTAMPTZOID;
        types[1] = TIMESTAMPTZOID;
        types[2] = INT4OID;
        types[3] = INT4OID;

        Datum values[4];
        values[0] = PG_GETARG_TIMESTAMPTZ(0);
        values[1] = PG_GETARG_TIMESTAMPTZ(1);
        values[2] = PG_GETARG_INT32(2);
        values[3] = PG_GETARG_INT32(3);

        SPI_connect();
        SPI_cursor_open_with_args("level1", "select * from obanalytics.level1 where microtimestamp between $1 and $2 and pair_id = $3 and exchange_id = $4 order by microtimestamp", 4, types, values, NULL, true, 0);
        SPI_finish();

        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();

    attinmeta = funcctx->attinmeta;

    SPI_connect();
    Portal portal = SPI_cursor_find("level1");
    SPI_cursor_fetch(portal, true, 1);
    uint64 proc = SPI_processed;

    if(proc == 1 && SPI_tuptable != NULL ) {

        SPITupleTable *tuptable = SPI_tuptable;
        TupleDesc tupdesc = tuptable->tupdesc;
        HeapTuple tuple_in = tuptable->vals[0];
        char **values = (char **) SPI_palloc(tupdesc->natts * sizeof(char *));

        int i;
        for (i = 1; i <= tupdesc->natts; i++) {
            values[i-1] = SPI_getvalue(tuple_in, tupdesc, i);
        }
        SPI_finish();

        HeapTuple tuple_out = BuildTupleFromCStrings(attinmeta, values);
        Datum result = HeapTupleGetDatum(tuple_out);

        SRF_RETURN_NEXT(funcctx, result);

    }
    else    {   /* do when there is no more left */
        SPI_cursor_close(SPI_cursor_find("level1"));
        SPI_finish();
        SRF_RETURN_DONE(funcctx);
    }
}
