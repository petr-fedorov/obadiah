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
#include "spread.h"
namespace obad {

class level2_impl {
};	  


level2::level2(TimestampTz m, price p, amount a){
};


level2::level2(level2&& o) {
};

level2::~level2() {
/*    if(!p_impl)
	  delete p_impl;*/
};

bool level2::operator < (const level2 & o) {
    return true;
};

char side() {
    return 'a';
};


HeapTuple level1::to_heap_tuple(AttInMetadata *attinmeta, int32 pair_id, int32 exchange_id) {
    char **values = (char **)palloc(7*sizeof(char *));
    static const int BUFFER_SIZE = 128;
    values[0] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[1] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[2] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[3] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[4] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[5] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    values[6] = (char *)palloc(BUFFER_SIZE*sizeof(char));
    snprintf(values[0],BUFFER_SIZE, "%Lf", best_bid_price);
    snprintf(values[1],BUFFER_SIZE, "%Lf", best_bid_qty);
    snprintf(values[2],BUFFER_SIZE, "%Lf", best_ask_price);
    snprintf(values[3],BUFFER_SIZE, "%Lf", best_ask_qty);
    snprintf(values[4],BUFFER_SIZE, "%s", timestamptz_to_str(microtimestamp));
    snprintf(values[5],BUFFER_SIZE, "%i", pair_id);
    snprintf(values[6],BUFFER_SIZE, "%i", exchange_id);
    HeapTuple tuple = BuildTupleFromCStrings(attinmeta, values);
    pfree(values[0]);
    pfree(values[1]);
    pfree(values[2]);
    pfree(values[3]);
    pfree(values[4]);
    pfree(values[5]);
    pfree(values[6]);
    pfree(values);
    return tuple;
};

level2_episode::level2_episode(Datum start_time, Datum end_time, Datum pair_id, Datum exchange_id, Datum frequency){

    Oid types[5];
    types[0] = TIMESTAMPTZOID;
    types[1] = INT4OID;
    types[2] = INT4OID;

    Datum values[5];
    values[0] = start_time;
    values[1] = pair_id;
    values[2] = exchange_id; 
    portal = SPI_cursor_open_with_args(INITIAL, R"QUERY(
					  select ts as microtimestamp, ob.price, ob.side, sum(ob.amount) as amount 
					  from obanalytics.order_book($1, $2, $3, p_only_makers := false, p_before := true, p_check_takers := false) join unnest(ob) ob on true
					  group by 1,2,3
					  order by price
						)QUERY", 4, types, values, NULL, true, 0);

    types[0] = TIMESTAMPTZOID;
    types[1] = TIMESTAMPTZOID;
    types[2] = INT4OID;
    types[3] = INT4OID;

    values[0] = start_time;
    values[1] = end_time;
    values[2] = pair_id;
    values[3] = exchange_id; 
    if(frequency != NULL_FREQ) {
	types[4] = INTERVALOID;
	values[4] = frequency;
	SPI_cursor_open_with_args(CURSOR,R"QUERY(
	  select microtimestamp, dc.*, row_number() over (partition by microtimestamp order by price, side) as episode_seq_no, count(*) over (partition by microtimestamp) as episode_size
	  from obanalytics.depth_change_by_episode($1, $2, $3, $4, $5) join unnest(depth_change) dc on true
	  order by microtimestamp, price, side 
	  )QUERY", 5, types, values, NULL, true, 0);
    }
    else {
	SPI_cursor_open_with_args(CURSOR,R"QUERY(
	  select microtimestamp, dc.*, row_number() over (partition by microtimestamp order by price, side) as episode_seq_no, count(*) over (partition by microtimestamp) as episode_size
	  from obanalytics.depth_change_by_episode($1, $2, $3, $4) join unnest(depth_change) dc on true
	  order by microtimestamp, price, side 
	  )QUERY", 4, types, values, NULL, true, 0);
    }
}

level2_episode::level2_episode() {
    portal = SPI_cursor_find(CURSOR);
}

std::vector<level2> level2_episode::next() {
    SPI_cursor_fetch(portal, true, 100);
    if(SPI_processed > 0){
	  return std::vector<level2> {};
    }
    else
	  throw 0;
}

std::vector<level2> level2_episode::initial() {
    std::vector<level2> result {next()};
    SPI_cursor_close(portal);
    portal = nullptr;
    return result;
}

level1 depth::spread() {
    level1 result{};
    result.best_bid_price = 1;
    return result;
}
	  

level1 depth::update(std::vector<level2> v) {
    return level1 {};
};

void * depth::operator new(size_t s) {
    return palloc(s);
};

void depth::operator delete(void *p, size_t s) {
    pfree(p);
};


}
