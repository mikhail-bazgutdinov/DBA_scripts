select 'alter database rename file '''||name||''' to '''||replace(name,'P01','Q01')||''';' from v$datafile

select 'alter database rename file '''||name||''' to '''||replace(name,'P01','Q01')||''';' from v$tempfile

select 'alter database rename file '''||member||''' to '''||replace(member,'P01','Q01')||''';' from v$logfile
