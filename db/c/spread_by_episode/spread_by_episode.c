#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(spread_by_episode);

Datum
spread_by_episode(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    int                  call_cntr;
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

        SPI_connect();
        SPI_cursor_open_with_args("level1", "select * from obanalytics.level1_bitfinex_btcusd order by microtimestamp limit 2", 0, NULL, NULL, NULL, true, 0);
        SPI_finish();

        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();

    call_cntr = funcctx->call_cntr;
    elog(DEBUG1, "call_cntr: %i", call_cntr);

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
