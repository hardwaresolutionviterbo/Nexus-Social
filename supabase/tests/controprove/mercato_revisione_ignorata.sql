-- Difetto introdotto apposta: gli annunci in revisione diventano visibili a tutti.
-- Deve far fallire M4.
drop policy "annunci in revisione nascosti" on public.listings;
