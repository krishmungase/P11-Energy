# Data preparation report

Source file: `time_series_60min_singleindex.csv`, 50,400 hourly rows used (2015-01-01 to the end of the file).
Long rows possible: 1,512,000. Rows dropped (empty cell, or a country-year we excluded): 31,075. Bad values removed: 70 (10 spikes, 60 load dips). Rows kept: 1,480,855.

`energy_full.csv`: 1,480,855 rows, 52.9 MB
`energy_sample.csv` (2019 only): 262,011 rows, 9.4 MB

## Rows dropped per country (empty cells; IT also includes all of 2015, which we excluded)

| country | load | solar | wind | how wind was built |
|---|---|---|---|---|
| DE | 0 | 103 | 74 | total column, gaps filled with onshore+offshore |
| FR | 43 | 14 | 7 | onshore only (no offshore column) |
| ES | 22 | 16 | 16 | onshore only (no offshore column) |
| IT | 8761 | 8777 | 8770 | onshore only (no offshore column) |
| GR | 37 | 47 | 35 | onshore only (no offshore column) |
| BE | 0 | 15 | 3934 | total column, gaps filled with onshore+offshore |
| AT | 0 | 61 | 48 | onshore only (no offshore column) |
| DK | 2 | 11 | 2 | total column, gaps filled with onshore+offshore |
| CZ | 109 | 35 | 15 | onshore only (no offshore column) |
| PT | 38 | 45 | 38 | onshore + offshore (offshore empty before Jun 2020 = 0) |

## Rows kept per country

| country | load | solar | wind |
|---|---|---|---|
| DE | 50400 | 50297 | 50326 |
| FR | 50356 | 50386 | 50393 |
| ES | 50375 | 50384 | 50384 |
| IT | 41639 | 41623 | 41630 |
| GR | 50363 | 50353 | 50365 |
| BE | 50400 | 50385 | 46466 |
| AT | 50345 | 50339 | 50352 |
| DK | 50389 | 50389 | 50396 |
| CZ | 50291 | 50365 | 50385 |
| PT | 50362 | 50355 | 50362 |

## Bad values removed

Whole bad days (every load hour of the day removed):

- AT 2015-11-29: 24 hours, average 1,913 MW
- AT 2015-12-25: 24 hours, average 2,366 MW

Single readings:

| timestamp (UTC) | country | metric | value | median of the 7 hours around it | reason |
|---|---|---|---|---|---|
| 2015-01-21 02:00 | AT | load | 3,767 | 4,357 | dip: below 50% of the 25 hours around it |
| 2015-12-28 23:00 | AT | load | 2,038 | 2,038 | dip: below 50% of the 25 hours around it |
| 2015-12-29 00:00 | AT | load | 1,840 | 1,840 | dip: below 50% of the 25 hours around it |
| 2015-12-29 01:00 | AT | load | 1,671 | 1,840 | dip: below 50% of the 25 hours around it |
| 2015-12-29 02:00 | AT | load | 1,627 | 1,840 | dip: below 50% of the 25 hours around it |
| 2015-12-29 03:00 | AT | load | 1,664 | 1,840 | dip: below 50% of the 25 hours around it |
| 2015-12-29 04:00 | AT | load | 2,012 | 2,012 | dip: below 50% of the 25 hours around it |
| 2015-11-30 14:00 | DK | load | 8,607 | 4,997 | spike: far above normal range and the 7 hours around it |
| 2017-05-08 06:00 | DK | load | 7,389 | 4,096 | spike: far above normal range and the 7 hours around it |
| 2017-05-08 07:00 | DK | load | 8,088 | 4,096 | spike: far above normal range and the 7 hours around it |
| 2018-01-17 08:00 | DK | load | 7,398 | 5,168 | spike: far above normal range and the 7 hours around it |
| 2018-02-06 12:00 | DK | load | 7,731 | 5,373 | spike: far above normal range and the 7 hours around it |
| 2018-03-22 08:00 | DK | load | 7,456 | 5,041 | spike: far above normal range and the 7 hours around it |
| 2019-05-01 15:00 | DK | load | 1,705 | 3,319 | dip: below 70% of the 7 hours around it |
| 2019-05-01 16:00 | DK | load | 1,693 | 3,319 | dip: below 70% of the 7 hours around it |
| 2020-02-27 09:00 | DK | load | 9,618 | 5,130 | spike: far above normal range and the 7 hours around it |
| 2017-05-08 06:00 | DK | wind | 7,237 | 3,506 | spike: far above normal range and the 7 hours around it |
| 2017-05-08 07:00 | DK | wind | 7,821 | 3,506 | spike: far above normal range and the 7 hours around it |
| 2015-03-26 08:00 | ES | load | 21,218 | 32,876 | dip: below 70% of the 7 hours around it |
| 2015-08-26 17:00 | ES | load | 18,616 | 31,803 | dip: below 70% of the 7 hours around it |
| 2018-06-05 10:00 | ES | load | 19,964 | 31,028 | dip: below 70% of the 7 hours around it |
| 2020-07-07 17:00 | FR | load | 158,000 | 47,869 | spike: far above normal range and the 7 hours around it |

## Rows per year

| year | rows |
|---|---|
| 2015 | 235,783 |
| 2016 | 262,435 |
| 2017 | 262,161 |
| 2018 | 262,014 |
| 2019 | 262,011 |
| 2020 | 196,451 |
