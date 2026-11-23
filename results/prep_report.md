# Data preparation report

Source file: `time_series_60min_singleindex.csv`, 50,400 hourly rows used (2015-01-01 to the end of the file).
Long rows possible: 1,512,000. Rows dropped (empty cell, or a country-year we excluded): 31,075. Rows kept: 1,480,925.

`energy_full.csv`: 1,480,925 rows, 52.9 MB
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
| FR | 50357 | 50386 | 50393 |
| ES | 50378 | 50384 | 50384 |
| IT | 41639 | 41623 | 41630 |
| GR | 50363 | 50353 | 50365 |
| BE | 50400 | 50385 | 46466 |
| AT | 50400 | 50339 | 50352 |
| DK | 50398 | 50389 | 50398 |
| CZ | 50291 | 50365 | 50385 |
| PT | 50362 | 50355 | 50362 |

## Rows per year

| year | rows |
|---|---|
| 2015 | 235,841 |
| 2016 | 262,435 |
| 2017 | 262,165 |
| 2018 | 262,018 |
| 2019 | 262,013 |
| 2020 | 196,453 |
