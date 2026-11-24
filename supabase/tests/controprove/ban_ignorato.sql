-- Difetto introdotto apposta: chi è bannato continua a pubblicare annunci e commenti.
-- Deve far fallire GS4.
drop trigger if exists listings_block_banned on public.listings;
drop trigger if exists listing_comments_block_banned on public.listing_comments;
