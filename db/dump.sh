pg_dump -U ob-analytics -d $1 -n bitfinex -s -T bitfinex.*00000* -T bitfinex.*_2019_* -T bitfinex.*default* > bitfinex_schema.sql
pg_dump -U ob-analytics -d $1 -n bitstamp -s  > bitstamp_schema.sql
pg_dump -U ob-analytics -d $1 -t bitstamp.pairs -a > bitstamp_pairs.sql
pg_dump -U ob-analytics -d $1 -n obanalytics -s > obanalytics_schema.sql
pg_dump -U ob-analytics -d $1 -t obanalytics.pairs -a > obanalytics_pairs.sql
