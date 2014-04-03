CREATE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sha1(bytea)
RETURNS character varying AS
$BODY$
BEGIN
RETURN ENCODE(DIGEST($1, 'sha1'), 'hex');
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION md5(bytea)
RETURNS character varying AS
$BODY$
BEGIN
RETURN ENCODE(DIGEST($1, 'md5'), 'hex');
END;
$BODY$
LANGUAGE 'plpgsql';