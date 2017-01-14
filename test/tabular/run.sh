ssconvert -S ./test/data.gnumeric data.csv
dart test/run.dart
rm data.csv.*
