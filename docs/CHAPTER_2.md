# Capítulo 2 — «Oro verde»

Chapter one ended with the Caja Poniente job ("poniente"): Ferrer's bribe money was
gone, Rubén "el del Puerto" was finished, and Alba left by boat for Marina del Este
saying "esto no ha terminado". Chapter two opens with the town's power vacuum. A
Málaga property developer has moved in and bought what Ferrer's corruption put up
for sale.

All chapter-two missions are data only (`data/missions/*.json` + `index.json`) and use
the existing `MissionController` objective types. The chain starts with
`requires: ["poniente"]`.

## New characters

| Character | Role | In game |
|---|---|---|
| **Rocío Almansa** | Freelance journalist for a local paper. She is sharp and short on money, and she wants what the bank job uncovered: where the money went *after* Ferrer. She is the player's main contact this chapter. | Contact `Rocio` («Rocío · Periodista»), Plaza Marruecos (12, −305), blip **R** |
| **Curro Maldonado** | Avocado and mango farmer from the vega. The council expropriated his family's farm ("interés general") and handed it to Altamar. He is stubborn and funny, and has nothing left to lose. | Contact `Curro` («Curro · Agricultor»), lower Calle Virgen del Carmen (175, −445), blip **C** |
| **Álvaro Cifuentes, "el Malagueño"** | Property developer from Málaga and owner of Inversiones Altamar. He bought Construcciones Mar Azul (the builder that paid Ferrer, already in the game as the Edificio Mar Azul office with its "Residencial Altamar (recalificado)" model), moorings in the marina and the expropriated farms. He launders money by exporting fruit at "4.000 € el kilo". | Antagonist. Appears in dialogue and at the San Cristóbal meeting, and flees by boat in mission 3 |
| **Sargento Damián Robles** | Corrupt Guardia Civil sergeant. He keeps Altamar's trucks off the N-340 and is paid by the envelope. His patrol is what the wanted level represents in these missions. | Antagonist's protector, chased in mission 3 |
| **Óscar Lledó** | Cifuentes's nervous accountant. He drives a green saloon and keeps visiting the notary. | Tail target in mission 1 |

Returning characters: **Paco** lends his RIB again, **Alba** calls in from Marina del Este and comes
back for the second act, and **Inés** follows the money on paper.

## Themes

- **The money doesn't vanish, it changes hands.** Taking Ferrer down left a vacuum, and capital from the big
  city fills it faster than any local thug could.
- **Land, water and the coast as loot.** Rezoned plots, expropriated farms and marina moorings: the
  Costa Tropical's beauty becomes a laundering machine. The avocado is "oro verde" (green gold), and the
  crates weigh more than the fruit.
- **Who guards the guards.** A corrupt sergeant means the player can't trust the uniform. The wanted
  level is literally Robles's men.
- **Proof versus force.** Rocío needs evidence that holds up in court and on the front page. The player
  has to learn to tail, photograph and keep things whole, not only to break them.

## Outline (10 beats)

Implemented missions are marked **[IMPLEMENTED]**, with their mission id.

1. **La sombra** — Rocío — **[IMPLEMENTED: `la_sombra`, 1800 €]**
   Rocío meets the player in the Plaza Marruecos and explains the new order: Cifuentes, Altamar and the
   money nobody can trace. In her little hatchback the player tails Lledó's green saloon through the old
   town. The player has to catch up before he vanishes into traffic (timed) and get close enough to read the
   plate (timed, "sin chocar"). The plate traces to Inversiones Altamar, and an overheard call names a
   meeting at San Cristóbal "with the sergeant". The player gets there first without police attention,
   climbs the Peñón steps on foot and photographs Cifuentes handing Sergeant Robles an envelope. Robles
   spots the camera (2★), the player loses the Guardia Civil and brings the photos to Rocío.

2. **Oro verde** — Curro — **[IMPLEMENTED: `la_finca`, 2500 €]**
   Curro tells how his family's farm was taken. The "camión de la finca" from the meeting is being loaded
   today. The player drives to the top of Calle Virgen del Carmen and is given an SMG. A foreman and five
   armed guards defend the Finca El Aguacatal. After clearing them, the player searches the warehouse:
   vacuum-packed cash under the avocados, plus Altamar export delivery notes. The player takes the loaded
   4x4, and Robles's patrol comes up the hill (2★). The player shakes them off without wrecking the cargo
   and delivers it to Curro.

3. **Mar de fondo** — Rocío — **[IMPLEMENTED: `mar_de_fondo`, 4000 €, end of the opening act]**
   Cifuentes is running tonight with the briefcase holding the contracts, the mooring deeds and the
   envelope list. Robles escorts him to San Cristóbal beach. In Alba's orange sports car the player runs
   down the sergeant's 4x4 (2★). Robles getting away resets to the checkpoint. Cifuentes has already gone
   ahead, so the player races to the beach against the clock, swims to Paco's RIB and chases Cifuentes's
   launch off the Peñón. With the launch disabled and Cifuentes in the water, the player grabs the
   briefcase, loses the police and comes ashore. Alba calls: she's coming back.

4. **Libro mayor** — Inés
   Inés recognises Altamar's shell companies from the casino ledgers. The player enters the Edificio Mar
   Azul office (planta 3) at night to copy the server and crack the office safe while security guards do
   their rounds. The player then escapes over the rooftops of the Torre Mediterráneo block.

5. **Amarres** — Paco
   Paco's fishermen are being pushed out of their moorings for Altamar's yachts. The player sabotages the
   developer's "floating office", a moored yacht used to count cash, then outruns the security RIBs in Paco's
   fishing boat.

6. **Fiesta en Jaime Playa** — Marina
   Cifuentes's lawyers throw a party at Jaime Playa to win over the council's new majority. Marina gets the
   player in as staff. The player spikes the sound system with Rocío's recording and has to get out before
   the bodyguards close the doors.

7. **Riego** — Curro
   Altamar diverts the vega's irrigation water to its new plantations. The player escorts Curro's tractor
   convoy to the sluice gate and holds it against Robles's off-duty "volunteers" until the water runs back
   to the small farms.

8. **El cuartel** — Alba
   Alba is back. Robles keeps the envelopes, and a list of who in Málaga takes them, in a locker at the
   post. The player starts a distraction in town (wanted level as a tool) while Alba walks in with a fake
   complaint. The player then drives the getaway with the locker contents.

9. **Recalificación** — Rocío
   The council meets to approve Residencial Altamar. With the evidence from the previous beats, the player
   has to get Rocío and Inés to the town hall in the Plaza de la Constitución through Altamar's hired thugs
   and a staged traffic jam. A protection and escort mission.

10. **Levante** — Alba (chapter finale)
    Cifuentes, out on bail, tries to leave with the last of the money by helicopter from the Torre
    Mediterráneo roof while Robles's men hold the street. The finale has three stages: an assault up the
    tower, a fight on the roof, and a final car-to-boat chase along the whole coast to Marina del Este.
    It ends with Robles arrested by his own colleagues and Cifuentes in the paper and in court.

## Implementation notes

- Index: `la_sombra` (Rocío, R, `5ec8a0`, requires `poniente`) → `la_finca` (Curro, C, `9bc53d`) →
  `mar_de_fondo` (Rocío, R, `e0645a`, finale colour like Poniente). Rocío and Curro are spawned from the
  index `contacts` block and offer nothing until Poniente is complete, so chapter one plays as before.
- Places: Plaza Marruecos (12, −305); Plaza San Cristóbal (−330, 236) and the Peñón steps (−357, 270);
  Finca El Aguacatal at the top of Calle Virgen del Carmen (≈215, −550, open hillside); San Cristóbal beach
  (−302, 240). Paco's RIB waits in the water at (−288, 258), and Cifuentes's launch loops in open sea
  east of the Peñón.
- Mechanics used: `talk_to`, `enter_vehicle`, `reach_area` (`marker_target`, `requires_vehicle`,
  `requires_on_foot`, `requires_no_wanted`, `time_limit`, `vehicle`), `wait` (stake-out, with `set_wanted`),
  `beat_up` (armed guards), `escape_police`, `destroy_vehicle` (car and boat, with `escape_distance`),
  `give_weapon`, `set_wanted`, spawns of kinds `vehicle` (traffic, parked, boats with `route`) and `enemy`.
- The framework has no "spotted" sensor, so tailing uses timed catch-up/read-the-plate steps,
  plus a "no police" condition for reaching the meeting.
- Test: `tests/chapter2.gd` (`GAME_DIR=… ~/gt.sh chapter2`) checks positions (cars near roads, people on
  land, boats and routes in deep water). It plays all three missions programmatically, including a
  timeout reset and an escape reset, and checks rewards, no replay and save/load.
