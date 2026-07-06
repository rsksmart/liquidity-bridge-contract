# Test E11.2 — unclaimed peg-in triggers global slash

## Cases

1. **Slash fires.** Serviceable registered peg-in, no claim, resolve past deadline → all
   registered LPs slashed proportionally; user still forwarded `amount − fee` (E11.1).
2. **Unregistered → no slash.** Deposit to an unregistered address; resolve → no slash.
3. **Below minimum → no slash.** Amount below the Flyover minimum → no slash.
4. **Deadline anchor.** Move the registration block later than the deposit; assert the
   deadline is measured from registration, not deposit.
5. **Grace window.** An LP registered inside the grace window is excluded from the slash.
6. **Bootstrap.** Two-LP set, one offline → confirm the proportional slash math on the small
   set.
