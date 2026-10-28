# Cricsheet data

Ball-by-ball match data and the people register from [Cricsheet](https://cricsheet.org), used
by `tools/import_dataset.py --cricsheet data/cricsheet`. The files aren't in git (about
50 MB, and Cricsheet updates them), so download them here:

```
curl -o t20s_male_json.zip https://cricsheet.org/downloads/t20s_male_json.zip
curl -o odis_male_json.zip https://cricsheet.org/downloads/odis_male_json.zip
curl -o tests_male_json.zip https://cricsheet.org/downloads/tests_male_json.zip
curl -o people.csv https://cricsheet.org/register/people.csv
curl -o names.csv https://cricsheet.org/register/names.csv
```

Licence: Cricsheet data is available under the Open Data Commons Attribution License
(ODC-By 1.0). Credit Cricsheet in any public use and keep its notices: the README.txt and
LICENSE.txt inside each zip. `.gdignore` stops Godot importing this folder.
