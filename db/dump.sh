# Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation,  version 2 of the License

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.



pg_dump -U ob-analytics  -d $1 $2 -n bitfinex -s | cat header.sql - >${3:-.}/bitfinex_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n bitstamp -s  | cat header.sql - > ${3:-.}/bitstamp_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n get -s  | cat header.sql -   > ${3:-.}/get_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n parameters -s  | cat header.sql -   > ${3:-.}/parameters_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -t bitstamp.pairs -a   | cat header.sql - > ${3:-.}/bitstamp_pairs.sql
pg_dump -U ob-analytics  -d $1 $2 -n obanalytics -s -T obanalytics.level[1-3]_[0-9]{5}* -T obanalytics.matches_[0-9]{5}*   | cat header.sql - > ${3:-.}/obanalytics_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -t obanalytics.pairs -a   | cat header.sql - > ${3:-.}/obanalytics_pairs.sql
pg_dump -U ob-analytics  -d $1 $2 -t obanalytics.exchanges -a   | cat header.sql - > ${3:-.}/obanalytics_exchanges.sql
