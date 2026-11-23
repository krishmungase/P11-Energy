# Data preparation report

Source file: `time_series_60min_singleindex.csv`, 50,400 hourly rows used (2015-01-01 to the end of the file).
Long rows possible: 1,512,000. Rows dropped (empty cell, or a country-year we excluded): 31,075. Spikes removed: 10. Rows kept: 1,480,915.

`energy_full.csv`: 1,480,915 rows, 52.9 MB
`energy_sample.csv` (2019 only): 262,013 rows, 9.4 MB

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
| ES | 50378 | 50384 | 50384 |
| IT | 41639 | 41623 | 41630 |
| GR | 50363 | 50353 | 50365 |
| BE | 50400 | 50385 | 46466 |
| AT | 50400 | 50339 | 50352 |
| DK | 50391 | 50389 | 50396 |
| CZ | 50291 | 50365 | 50385 |
| PT | 50362 | 50355 | 50362 |

## Spikes removed (single-hour data errors)

| timestamp (UTC) | country | metric | value | median of the 7 hours around it |
|---|---|---|---|---|
| 2015-11-30 14:00 | DK | load | 8,607 | 4,997 |
| 2017-05-08 06:00 | DK | load | 7,389 | 4,096 |
| 2017-05-08 07:00 | DK | load | 8,088 | 4,096 |
| 2018-01-17 08:00 | DK | load | 7,398 | 5,168 |
| 2018-02-06 12:00 | DK | load | 7,731 | 5,373 |
| 2018-03-22 08:00 | DK | load | 7,456 | 5,041 |
| 2020-02-27 09:00 | DK | load | 9,618 | 5,130 |
| 2017-05-08 06:00 | DK | wind | 7,237 | 3,506 |
| 2017-05-08 07:00 | DK | wind | 7,821 | 3,506 |
| 2020-07-07 17:00 | FR | load | 158,000 | 47,869 |

## Rows per year

| year | rows |
|---|---|
| 2015 | 235,840 |
| 2016 | 262,435 |
| 2017 | 262,161 |
| 2018 | 262,015 |
| 2019 | 262,013 |
| 2020 | 196,451 |
