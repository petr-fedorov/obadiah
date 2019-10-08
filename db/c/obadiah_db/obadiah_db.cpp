// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 2 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


#ifdef __cplusplus
extern "C" {
#endif // __cplusplus
#include "postgres.h"
#include "utils/timestamp.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "catalog/pg_type_d.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(depth_change_by_episode);
PG_FUNCTION_INFO_V1(spread_by_episode);

#ifdef __cplusplus
}
#endif // __cplusplus

#include <vector>
#include <string>
#include <map>


namespace obadiah_db {

    using namespace std;

    template <class T>
    class spi_allocator
    {
    public:
        using value_type    = T;

    //     using pointer       = value_type*;
    //     using const_pointer = typename std::pointer_traits<pointer>::template
    //                                                     rebind<value_type const>;
    //     using void_pointer       = typename std::pointer_traits<pointer>::template
    //                                                           rebind<void>;
    //     using const_void_pointer = typename std::pointer_traits<pointer>::template
    //                                                           rebind<const void>;

    //     using difference_type = typename std::pointer_traits<pointer>::difference_type;
    //     using size_type       = std::make_unsigned_t<difference_type>;

    //     template <class U> struct rebind {typedef allocator<U> other;};

        spi_allocator() noexcept {   elog(INFO, "spi_allocator instantiated");}  // not required, unless used
        template <class U> spi_allocator(spi_allocator<U> const&) noexcept {}

        value_type*  // Use pointer if pointer is not a value_type*
        allocate(std::size_t n)
        {
            elog(INFO, "Allocated %lu", n*sizeof(value_type));
            return static_cast<value_type*>(SPI_palloc(n*sizeof(value_type)));
        }

        void
        deallocate(value_type* p, std::size_t n) noexcept  // Use pointer if pointer is not a value_type*
        {
            elog(INFO, "Deallocated: %lu", n*sizeof(value_type));
            SPI_pfree(p);
        }

    //     value_type*
    //     allocate(std::size_t n, const_void_pointer)
    //     {
    //         return allocate(n);
    //     }

    //     template <class U, class ...Args>
    //     void
    //     construct(U* p, Args&& ...args)
    //     {
    //         ::new(p) U(std::forward<Args>(args)...);
    //     }

    //     template <class U>
    //     void
    //     destroy(U* p) noexcept
    //     {
    //         p->~U();
    //     }

    //     std::size_t
    //     max_size() const noexcept
    //     {
    //         return std::numeric_limits<size_type>::max();
    //     }

    //     allocator
    //     select_on_container_copy_construction() const
    //     {
    //         return *this;
    //     }

    //     using propagate_on_container_copy_assignment = std::false_type;
    //     using propagate_on_container_move_assignment = std::false_type;
    //     using propagate_on_container_swap            = std::false_type;
    //     using is_always_equal                        = std::is_empty<allocator>;
    };

    template <class T, class U>
    bool
    operator==(spi_allocator<T> const&, spi_allocator<U> const&) noexcept
    {
        return true;
    }

    template <class T, class U>
    bool
    operator!=(spi_allocator<T> const& x, spi_allocator<U> const& y) noexcept
    {
        return !(x == y);
    }


    struct level3 {
        TimestampTz microtimestamp;
        int64 order_id;
        int32 event_no;
        char side;
        basic_string<char, char_traits<char>, spi_allocator<char>>  price;
        string amount;
        TimestampTz price_microtimestamp;

        level3 () {};

        level3(TimestampTz m, int64 o, int32 e, char s, char *p, char *a, TimestampTz p_m):
            microtimestamp(m), order_id(o), event_no(e), side(s), price(p), amount(a), price_microtimestamp(p_m) {};

        level3 (const level3 &e) :
            microtimestamp(e.microtimestamp),order_id(e.order_id), event_no(e.event_no), side(e.side), price(e.price),  amount(e.amount), price_microtimestamp(e.price_microtimestamp)
         {};


    };



    struct Depth {
        Depth() :fake_depth_change("{ \"(9860.0,0,b,)\", \"(9890.1,1,s,)\" }"), precision("r0") {};
        void start_episode(string microtimestamp) {
            episode = microtimestamp;

        };


        void process_level3(HeapTuple tuple, TupleDesc tupdesc) {
            bool is_null;
            level3 event {
                DatumGetTimestampTz(SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "microtimestamp"), &is_null)),
                DatumGetInt64(SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "order_id"), &is_null)),
                DatumGetInt32(SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "event_no"), &is_null)),
                DatumGetChar(SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "side"), &is_null)),
                SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "price")),
                SPI_getvalue(tuple, tupdesc, SPI_fnumber(tupdesc, "amount")),
                DatumGetTimestampTz(SPI_getbinval(tuple, tupdesc, SPI_fnumber(tupdesc, "price_microtimestamp"), &is_null))
                };

            by_order_id[event.order_id] = event;
        };

        string &end_episode() {
            // char *result = (char *)SPI_palloc(fake_depth_change.size()+1);
            // strcpy(result, fake_depth_change.c_str());
            //return result;
            return fake_depth_change;
            };

        string &get_precision() {
            return precision;
        }

        std::string fake_depth_change;
        std::string precision;
        string episode;
        map<int64, level3, less<int64>, spi_allocator<pair<int64, level3>>> by_order_id;

    };


}


Datum
depth_change_by_episode(PG_FUNCTION_ARGS)
{
    using namespace std;
    using namespace obadiah_db;

    FuncCallContext     *funcctx;
    TupleDesc            tupdesc;
    AttInMetadata       *attinmeta;

    if (SRF_IS_FIRSTCALL())
    {
        elog(INFO, "started depth_change_by_episode");
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
        SPI_cursor_open_with_args("level3", "select *\
                                             from obanalytics.level3\
                                             where microtimestamp between $1 and $2\
                                               and pair_id = $3\
                                               and exchange_id = $4\
                                             order by microtimestamp", 4, types, values, NULL, true, 0);

        funcctx->user_fctx = new((Depth *)SPI_palloc(sizeof(Depth))) Depth {};

        SPI_finish();
        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();

    MemoryContext   oldcontext;
    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);


    attinmeta = funcctx->attinmeta;
    Depth *depth = (Depth *) funcctx->user_fctx;

    SPI_connect();
    Portal portal = SPI_cursor_find("level3");

    SPI_cursor_fetch(portal, true, 1);

    uint64 proc = SPI_processed;

    if(proc == 1 && SPI_tuptable != NULL ) {

        TupleDesc tupdesc = SPI_tuptable->tupdesc;
        HeapTuple tuple_in = SPI_tuptable->vals[0];

        depth -> process_level3(tuple_in, tupdesc);

        char **values = (char **) SPI_palloc(5*sizeof(char *)); // obanalytics.level2 has 5 columns

        values[0] = SPI_getvalue(tuple_in, tupdesc, SPI_fnumber(tupdesc, "microtimestamp"));    // microtimestamp
        values[1] = SPI_getvalue(tuple_in, tupdesc, SPI_fnumber(tupdesc, "pair_id"));           // pair_id
        values[2] = SPI_getvalue(tuple_in, tupdesc, SPI_fnumber(tupdesc, "exchange_id"));       // exchange_id
        values[3] = (char *)depth->get_precision().c_str();                                     // precision
        values[4] = (char *)depth -> end_episode().c_str();                                     // depth_changes


        HeapTuple tuple_out = BuildTupleFromCStrings(attinmeta, values);
        Datum result = HeapTupleGetDatum(tuple_out);

        SPI_finish();
        MemoryContextSwitchTo(oldcontext);
        SRF_RETURN_NEXT(funcctx, result);

    }
    else    {   /* do when there is no more left */


        SPI_cursor_close(SPI_cursor_find("level3"));

        elog(INFO, "map size %lu", depth ->by_order_id.size());
        depth ->~Depth();
        SPI_pfree(depth);

        SPI_finish();
        MemoryContextSwitchTo(oldcontext);


        SRF_RETURN_DONE(funcctx);
    }
}




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
