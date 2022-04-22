DECLARE
CURSOR RECOMPILE_CUR 
  IS 
select
	case 
		when  object_type='SYNONYM' and owner='PUBLIC' then
			'ALTER PUBLIC SYNONYM "' || object_name || '" compile'
		when OBJECT_TYPE='PACKAGE BODY' then
			'alter package "' || owner||'"."'||OBJECT_NAME || '" compile body'
		else
			'alter ' || OBJECT_TYPE || ' "' || owner||'"."'||OBJECT_NAME || '" compile'
	end as cmd
from dba_objects 
where STATUS = 'INVALID' 
	and OBJECT_TYPE in ( 'PACKAGE BODY', 'PACKAGE', 'FUNCTION', 'PROCEDURE', 
	'TRIGGER', 'VIEW','MATERIALIZED VIEW', 'SYNONYM' ) order by OBJECT_TYPE, OBJECT_NAME; 

recompile_rec  RECOMPILE_CUR%ROWTYPE;                   
pe  NUMBER;

BEGIN
OPEN RECOMPILE_CUR; 
LOOP 
  FETCH RECOMPILE_CUR INTO recompile_rec; 
  EXIT WHEN RECOMPILE_CUR%NOTFOUND; 
	 begin
	  EXECUTE IMMEDIATE recompile_rec.cmd;
	  EXCEPTION 
	   when OTHERS then NULL;
	 end;          
END LOOP; 
CLOSE RECOMPILE_CUR; 
end;
/
