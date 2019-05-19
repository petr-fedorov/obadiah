
pg_dump -U ob-analytics -d $1 -n bitfinex -s -T bitfinex.*00000*  > ${2:-.}/bitfinex_schema.sql
pg_dump -U ob-analytics -d $1 -n bitstamp -s  > ${2:-.}/bitstamp_schema.sql
pg_dump -U ob-analytics -d $1 -t bitstamp.pairs -a > ${2:-.}/bitstamp_pairs.sql
pg_dump -U ob-analytics -d $1 -n obanalytics -s > ${2:-.}/obanalytics_schema.sql
pg_dump -U ob-analytics -d $1 -t obanalytics.pairs -a > ${2:-.}/obanalytics_pairs.sql
pg_dump -U ob-analytics -d $1 -t obanalytics.exchanges -a > ${2:-.}/obanalytics_exchanges.sql
