CREATE TABLE virtual_domains (
	id SERIAL NOT NULL,
	name VARCHAR(50) NOT NULL,
	quota_mb INTEGER NOT NULL DEFAULT 0,
	system_gid INTEGER NOT NULL,
	system_uid INTEGER NOT NULL,
	active INTEGER NOT NULL DEFAULT 1,
	PRIMARY KEY(id),
	CONSTRAINT UNIQUE_SYSTEM_GID UNIQUE (system_gid),
	CONSTRAINT UNIQUE_SYSTEM_UID UNIQUE (system_uid)
);

CREATE TABLE virtual_users (
	id SERIAL NOT NULL,
	domain INTEGER NOT NULL,
	account VARCHAR(40) NOT NULL,
	password VARCHAR(32) NOT NULL,
	quota_mb INTEGER NOT NULL DEFAULT 0,
	active INTEGER NOT NULL DEFAULT 1,
	PRIMARY KEY(id),
	FOREIGN KEY (domain) REFERENCES virtual_domains(id) ON DELETE CASCADE,
	CONSTRAINT UNIQUE_EMAIL UNIQUE (domain, account)
);

CREATE TABLE virtual_aliases (
	id SERIAL NOT NULL,
	domain INTEGER NOT NULL,
	source VARCHAR(40) NOT NULL,
	destination VARCHAR(80) NOT NULL,
	active INTEGER NOT NULL DEFAULT 1,
	PRIMARY KEY(id),
	FOREIGN KEY (domain) REFERENCES virtual_domains(id) ON DELETE CASCADE
);

-- triggers

CREATE OR REPLACE FUNCTION alias_cleanup() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
	NEW.source := trim(both FROM lower(NEW.source));
	NEW.destination := trim(both FROM lower(NEW.destination));

	RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE TRIGGER alias_cleanup BEFORE INSERT OR UPDATE ON virtual_aliases FOR EACH ROW EXECUTE PROCEDURE alias_cleanup();


CREATE OR REPLACE FUNCTION domain_cleanup() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
	NEW.name := trim(both FROM lower(NEW.name));

	RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE TRIGGER domain_cleanup BEFORE INSERT OR UPDATE ON virtual_domains FOR EACH ROW EXECUTE PROCEDURE domain_cleanup();


CREATE OR REPLACE FUNCTION user_cleanup() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
	NEW.account := trim(both FROM lower(NEW.account));

	RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE TRIGGER user_cleanup BEFORE INSERT OR UPDATE ON virtual_users FOR EACH ROW EXECUTE PROCEDURE user_cleanup();

-- functions

CREATE OR REPLACE FUNCTION alias_destination(in_username TEXT, in_domain TEXT) RETURNS SETOF TEXT AS $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temprec record;
BEGIN
	FOR temprec in
		SELECT a.destination
		FROM virtual_aliases a JOIN virtual_domains d ON a.domain = d.id and d.active = 1
		WHERE a.active = 1 AND a.source = use_username AND d.name = use_domain
	LOOP
		RETURN NEXT temprec.destination;
	END LOOP;

	RETURN;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION domain_is_local(in_domain TEXT) RETURNS TEXT AS $BODY$
DECLARE
	use_domain text := trim(both FROM lower(in_domain));
	temp_id INTEGER;
BEGIN
	SELECT d.id INTO temp_id
	FROM virtual_domains d
	WHERE d.active = 1 AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN in_domain;
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION domain_quota(in_domain TEXT) RETURNS TEXT AS $BODY$
DECLARE
	use_domain text := trim(both FROM lower(in_domain));
	temp_text TEXT;
BEGIN
	SELECT d.quota_mb::TEXT || 'M' INTO temp_text
	FROM virtual_domains d
	WHERE d.active = 1 AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN temp_text;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_is_local(in_username TEXT, in_domain TEXT) RETURNS TEXT AS $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temp_id INTEGER;
BEGIN
	SELECT u.id INTO temp_id
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN in_username || '@' || in_domain;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_maildir(in_username TEXT, in_domain TEXT) RETURNS TEXT AS $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temp_text TEXT;
BEGIN
	temp_text := user_is_local(in_username, in_domain);

	IF temp_text IS NULL THEN
		RETURN NULL;
	END IF;

	RETURN '/srv/mail/' || use_domain || '/' || use_username || '/maildir';
END;
$BODY$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION user_quota(in_username TEXT, in_domain TEXT) RETURNS TEXT AS $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temp_text TEXT;
BEGIN
	SELECT u.quota_mb::TEXT || 'M' INTO temp_text
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN temp_text;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_filter(in_username TEXT, in_domain TEXT) RETURNS TEXT as $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	reply TEXT;
BEGIN
	SELECT u.filter INTO reply
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN reply;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_gid(in_username TEXT, in_domain TEXT) RETURNS TEXT as $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	reply INTEGER;
BEGIN
	SELECT d.system_gid INTO reply
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN reply;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_uid(in_username TEXT, in_domain TEXT) RETURNS TEXT as $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	reply INTEGER;
BEGIN
	SELECT d.system_uid INTO reply
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN reply;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION user_password_verify(in_user TEXT, in_password TEXT) RETURNS INTEGER as $BODY$
DECLARE
	use_username TEXT;
	use_domain TEXT;
	temp_int INTEGER;
BEGIN
	use_username := split_part(in_user, '@', 1);
	use_domain := split_part(in_user, '@', 2);

	SELECT u.id INTO temp_int
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain AND u.password = md5(in_password);

	IF NOT FOUND THEN
		RETURN NULL;
	END IF;

	RETURN 1;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE TYPE type_dovecot_password AS (
	username TEXT,
	domain TEXT,
	password TEXT
);

CREATE OR REPLACE FUNCTION dovecot_password(in_username TEXT, in_domain TEXT) RETURNS SETOF type_dovecot_password as $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temp_record type_dovecot_password;
BEGIN
	SELECT use_username as username, use_domain as domain, u.password as password INTO temp_record
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN;
	END IF;

	RETURN NEXT temp_record;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE TYPE type_dovecot_user AS (
	gid INTEGER,
	uid INTEGER,
	home TEXT,
	mail TEXT,
	quota_rule TEXT
);

CREATE OR REPLACE FUNCTION dovecot_user(in_username TEXT, in_domain TEXT) RETURNS SETOF type_dovecot_user as $BODY$
DECLARE
	use_username text := trim(both FROM lower(in_username));
	use_domain text := trim(both FROM lower(in_domain));
	temp_record type_dovecot_user;
BEGIN
	SELECT
		d.system_gid AS gid,
		d.system_uid AS uid,
		'/srv/mail/' || d.name || '/' || u.account AS home,
		'maildir:/srv/mail/' || d.name || '/' || u.account || '/maildir' AS mail,
		'*:storage=' || u.quota_mb || 'M' AS quota_rule
	INTO temp_record
	FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
	WHERE u.active = 1 AND u.account = use_username AND d.name = use_domain;

	IF NOT FOUND THEN
		RETURN;
	END IF;

	RETURN NEXT temp_record;
END;
$BODY$
LANGUAGE 'plpgsql';


CREATE TYPE type_dovecot_iterate AS (
	"user" TEXT
);

CREATE OR REPLACE FUNCTION dovecot_iterate() RETURNS SETOF type_dovecot_iterate as $BODY$
DECLARE
	temp_record type_dovecot_iterate;
BEGIN
	FOR temp_record IN
		SELECT u.account || '@' || d.name AS "user"
		FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id AND d.active = 1
		WHERE u.active = 1
	LOOP
		RETURN NEXT temp_record;
	END LOOP;

	RETURN;
END;
$BODY$
LANGUAGE 'plpgsql';
