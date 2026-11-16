-- Difetto introdotto apposta: niente controllo iniziale delle richieste. Deve far fallire Z1.
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';
