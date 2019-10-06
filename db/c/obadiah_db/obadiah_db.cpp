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


namespace obadiah_db {


    template <class T>
    class allocator
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

        allocator() noexcept {   elog(INFO, "Created!");}  // not required, unless used
        template <class U> allocator(allocator<U> const&) noexcept {}

        value_type*  // Use pointer if pointer is not a value_type*
        allocate(std::size_t n)
        {
            elog(INFO, "Allocated!");
            return static_cast<value_type*>(SPI_palloc(n*sizeof(value_type)));
        }

        void
        deallocate(value_type* p, std::size_t) noexcept  // Use pointer if pointer is not a value_type*
        {
            elog(INFO, "Deallocated!");
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
    operator==(allocator<T> const&, allocator<U> const&) noexcept
    {
        return true;
    }

    template <class T, class U>
    bool
    operator!=(allocator<T> const& x, allocator<U> const& y) noexcept
    {
        return !(x == y);
    }

}

Datum
depth_change_by_episode(PG_FUNCTION_ARGS)
{
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
        SPI_cursor_open_with_args("level2", "select * from obanalytics.level2 where microtimestamp between $1 and $2 and pair_id = $3 and exchange_id = $4 order by microtimestamp", 4, types, values, NULL, true, 0);

        obadiah_db::allocator<int> a;

        funcctx->user_fctx = new(SPI_palloc(sizeof(std::vector<int,obadiah_db::allocator<int>>))) std::vector<int,obadiah_db::allocator<int>>(a);

        SPI_finish();



        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();


    attinmeta = funcctx->attinmeta;

    SPI_connect();
    Portal portal = SPI_cursor_find("level2");
    SPI_cursor_fetch(portal, true, 1);
    uint64 proc = SPI_processed;

    if(proc == 1 && SPI_tuptable != NULL ) {

        SPITupleTable *tuptable = SPI_tuptable;
        TupleDesc tupdesc = tuptable->tupdesc;
        HeapTuple tuple_in = tuptable->vals[0];
        char **values = (char **) SPI_palloc(tupdesc->natts * sizeof(char *));


        MemoryContext   oldcontext;
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        if(funcctx->user_fctx) ((std::vector<int> *)funcctx->user_fctx)->push_back(1);

        MemoryContextSwitchTo(oldcontext);



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

        MemoryContext   oldcontext;
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
        elog(INFO, "Size %lu", ((std::vector<int> *)funcctx->user_fctx)->size() );
        ((std::vector<int> *)funcctx->user_fctx)-> ~vector();
        MemoryContextSwitchTo(oldcontext);

        SPI_pfree(funcctx->user_fctx);
//        SPI_cursor_close(SPI_cursor_find("level2"));
        SPI_finish();
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
