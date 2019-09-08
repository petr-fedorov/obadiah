
pg_dump -U ob-analytics  -d $1 $2 -n bitfinex -s -T bitfinex.*00000*  > ${3:-.}/bitfinex_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n bitstamp -s  > ${3:-.}/bitstamp_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n get -s  > ${3:-.}/get_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -n parameters -s  > ${3:-.}/parameters_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -t bitstamp.pairs -a > ${3:-.}/bitstamp_pairs.sql
pg_dump -U ob-analytics  -d $1 $2 -n obanalytics -s > ${3:-.}/obanalytics_schema.sql
pg_dump -U ob-analytics  -d $1 $2 -t obanalytics.pairs -a > ${3:-.}/obanalytics_pairs.sql
pg_dump -U ob-analytics  -d $1 $2 -t obanalytics.exchanges -a > ${3:-.}/obanalytics_exchanges.sql
