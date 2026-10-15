# Steward

An inventory organizer for Final Fantasy XI (Windower 4): sorts your bags and wardrobes, Drop / Sell / Lot / Pass
lists, Porter Moogle storage, NPC trades (everything QuickTrade does), AH prices in its advice, a Zeni NM planner,
and a search across all your characters. Window: `//stw`. Commands: `//stw help`.

## Install

1. Download this page (green **Code** button > **Download ZIP**) and put the files in `Windower\addons\Steward\`
   (so you have `Windower\addons\Steward\Steward.lua`).
2. In game: `//lua load steward`. Nothing is moved until you say so: `//stw start` turns automatic sorting on,
   `//stw sort` does one pass.

## Updates

Steward checks this page when it loads and tells you when there's a newer version.
`//stw update install` downloads it (only Steward's own files; your settings and lists are never touched),
then `//lua r steward`. `//stw update off` stops the check.

## What it sends to the game

Item moves between your bags, the inventory "stack" request, trades to NPCs you stand next to, Treasury-style
drop / lot / pass, Porter Moogle store menus, and (only after you type `confirm`) buying Storage Slips from a
Porter Moogle for 1,000 gil each. Selling only happens through the separate SellNPC addon, from your Sell list.
Gear in your Mog Wardrobes is only ever moved between wardrobes: never traded, dropped, sold or stored.
Dropping can't be undone: new Drop-list items wait 10 seconds (click again to cancel), valuable-looking ones
need a second click. AH prices are read from ffxiah.com (default server Carbuncle: `//stw prices server <name>`).

---

# Steward

Keeps your bags organized automatically, per character, with a clickable in-game window.
Type `//stw` to show or hide the window. Drag it by its title line; use the mouse wheel on lists.

## The organization system

**Everything except wardrobe gear** has a home bag by category (change any of these on the **Rules** tab):

| Category | Default home | If full, then |
|---|---|---|
| Crystals & clusters | Mog Sack | Satchel, Case |
| Food, medicine, scrolls | Mog Satchel | Sack, Case |
| Crafting & loot materials | Mog Case | Sack, Satchel |
| Storage slips | Mog Case | (kept reachable for the Porter) |
| Currency, seals, vouchers | Mog Safe | Safe 2, Locker |
| Automaton attachments | Mog Sack | |
| Furniture & plants | Storage | Safe 2, Safe |
| Quest items & other | Mog Safe | Safe 2, Locker |
| Gear outside wardrobes | Mog Safe (in Mog House) | Safe 2, Storage, Locker |
| Linkshells & pearls | Leave in place | |

* **Gear outside the wardrobes** (weapons and armor in your inventory, Satchel, Sack or Case) is put
  into Safe → Safe 2 → Storage → Locker whenever you're in your Mog House. Equipped gear, Keep-list gear
  (warp rings etc.) and wardrobe gear are never moved. Gear already in one of those four bags stays put.
* **Inventory goal: 70 free slots** (or as close as possible). If fewer than 70 slots are free after normal
  sorting, extra items (anything not on the Keep list, not equipped and not set to "leave in place") are put
  away: home bag first, otherwise Satchel / Sack / Case. Loose items go before gear; nothing goes into a
  wardrobe. If only Keep-list and equipped items are left, it stops there. Change it with the [-] [+] on
  the Home tab or `//stw goal <n>` (0 = off).
* **Keep list**: items that always stay in your inventory (warp rings, Echo Drops, Remedies, ninja tools, food...).
* Mog Safe, Safe 2, Locker and Storage can only be opened in your Mog House, so items going to or
  from them wait until you're home. Satchel, Sack and Case work anywhere.

**Mog wardrobes are sorted by gear slot** (**Wardrobes** tab). With all 8 unlocked:

| Wardrobe | Gear |
|---|---|
| 1 | Weapons & shields |
| 2 | Head |
| 3 | Body |
| 4 | Hands |
| 5 | Legs |
| 6 | Feet |
| 7 | Neck, ears, rings, waist, back |
| 8 | Ranged & ammo |

With fewer wardrobes the groups are combined automatically. Wardrobe gear:
* only ever moves between wardrobes (through the inventory, one piece at a time),
* is put back into a wardrobe first if a move is interrupted (even after a crash or reload),
* is never sorted into another bag and is **never given to a Porter Moogle**.
* A full wardrobe just leaves gear where it is.

## Automation

**Nothing is sorted when Steward loads.** Type `//stw start` (or click **[Start]** on the Home tab) to turn
automatic sorting on for this session, or `//stw sort` for a single pass. `//stw stop` turns it off again.
It is off again every time you load or reload the addon.

While it's on, sorting runs by itself a few seconds after your bags change, but only while you're standing idle
(never while engaged, casting, zoning or in a cutscene). Equipped items and bazaar items are never moved.
Toggle each part on the **Home** tab or with `//stw auto <sort|wardrobes|drop|lotpass|stack>`.

## Split stacks

The same item in partial stacks in two places (e.g. Pebble x5 in the Sack and x4 in the Satchel) wastes a slot.
Every sort now merges them: it takes the smaller stack out and puts it onto the bigger one, preferring the
item's home bag. Mog House bags are only merged while you're at home; wardrobes, Keep-list items, held items
and categories set to `stay` or `inventory` are never touched. Inventory-only duplicates are still handled by
the game's own stack request. `//stw merge` lists split stacks and how many slots merging would gain;
`//stw merge off` turns it off. (Idea from **dupefind by Lili**.)

## Wardrobe audit (GearSwap vs wardrobes)

`//stw audit` reads your GearSwap files for this character (`GearSwap\data\<Name>_*.lua`, `<Name>-*.lua` and
`data\<Name>\`) and compares the gear they name with your wardrobes:

* **MISSING**: gear your files use that isn't in any wardrobe, and where it is instead (a bag, a Porter slip,
  or "not on this character").
* **UNUSED**: wardrobe gear none of those files name: room you could free up yourself.

`//stw audit blu` checks one job's files; `//stw audit all` checks every file in GearSwap\data (use this before
deciding something is unused, since another job may need it). Commented-out gear is ignored. The full list goes to
`data\audit_<Name>.txt`. Read only: nothing is moved, wardrobes stay isolated. (Idea from **Wardrobe9**.)

## Find across characters

`//stw find <text>` searches every bag of every character you've loaded Steward on: inventory, Mog House
bags, Satchel/Sack/Case, all 8 wardrobes and gear stored on Porter slips. Use part of a name (`//stw find nyame`),
a wildcard (`//stw find *crest`) or an item id. Results show each character, bag and count; other characters
show how old their saved list is. `//stw find` alone lists the saved characters; `//stw find forget <Name>`
removes one. Lists are saved to `data\chars\<Name>.lua` when bags change (at most every 30 s) and at
logout/unload, so log each character in with Steward loaded once to include it. Read only: nothing moves.
(Ideas from **findAll** and WoW's **Syndicator**/**BagSync**.)

## Several characters at once

Steward can run on all your characters at the same time. Every save re-reads `data\settings.xml` first, so one
character saving never undoes another character's lists, rules or goal (Windower's settings library on its own
writes every character's section as it was when *that* game loaded the addon).

## Safety stops

* The same error is shown in chat at most once a minute.
* **3 errors within 5 minutes**, an item **moving back and forth** between two bags, or **more than 6
  automatic sorts in 3 minutes** pauses all automation (sorting, dropping, lot/pass, stacking).
* You get one message saying why. The window shows **PAUSED [Resume]**; click it or type `//stw resume`.
* Automatic sorts are at least 10 seconds apart, and chat gets one summary line a minute at most.
* Full stacks only go into a free slot (never "topped up" onto a partial stack, which just leaves a new partial
  behind), and a stack is only moved between wardrobes if the whole stack fits, so ammo isn't split and moved again.
* After each move Steward waits until the game has actually applied it (up to 2.5 s) before planning the next,
  so a move is never sent twice when the server is slow.
* A bag that refuses an item 3 times (usually because it is really full) is treated as full for 30 minutes,
  and the item goes to its next bag instead. Bags are read in all 80 slots, so a Storage that holds more than
  its current size (after furniture is taken down) counts as full.

## Activity log

Every move (item, from bag/slot, to bag, and why), skip, sort start/end with bag counts, error, pause,
porter step and drop/lot/pass is written to:

`Windower\addons\Steward\data\logs\<Name>_<date>.log`

`//stw log` shows the file's location; `//stw log off` turns it off.

## Next steps: sell, toss or store

After every manual sort (and after automatic sorts when something changed) you get one chat line, e.g.
`Next steps: Sell 4 (Bat Wing, Pebble, ...) | Toss 1 (...) | Store 3 at a Porter`. Details are on the **Advice** tab
or `//stw advice`:

* **Sell**: materials and furniture that can be sold (never currencies such as Byne Bills or coins), with where: "check AH, else NPC", "sell to an NPC"
  (can't be auctioned) or "AH or bazaar (no NPC)".
* **Toss?**: Ex items an NPC won't buy. Names that are usually upgrade materials or currencies are never suggested
  (vouchers, abjurations, Abdhaljs items, seals, crest cards, keys, souls, shards, coffers, NM drops like horns/wings/
  scales...), nor are items an NPC stores for you. Only toss what you're done with. Click one twice to add it to the
  Drop list.
* `//stw advice ignore add <item>` hides an item from every suggestion (`remove` undoes it, `//stw advice ignore` lists).
* **Store**: gear a Porter Moogle can hold (slip number shown). **[Store at Porter]** stores them.
* **Duplicates**: extra copies of gear you already keep in a wardrobe.

Never suggested: wardrobe gear, Keep-list, equipped, quest, currency, slip, linkshell, crystal, automaton and
food/medicine items. **[Gather sell items]** (or `//stw sellprep`) pulls the Sell items into your inventory and
holds auto-sort for 10 minutes so they stay there while you sell; `//stw unhold` ends it early.

## Window

Hover the mouse over anything clickable (tabs, buttons, list items) and it lights up in yellow on a lighter row, so
you can see exactly what a click will do. The Drop list picker does the same for each item.

## Rules tab: 2nd and 3rd bags

Each kind of item has the bag it's kept in, plus a **2nd** and **3rd** bag used when the ones before are full.
Click a bag to step through the choices (`-` = none). Grey 2nd/3rd bags are automatic (as before); clicking turns
them into your own. **[2nd/3rd back to automatic]** resets them. Items already sitting in one of their bags are left
where they are, so changing the 2nd/3rd only decides where *new* items go. (Taking a bag off the list does make the
next sort move what's in it.) Automatic gear uses Safe 2, Storage and Locker (`+more`).

## Drop list picker (big list)

`//stw picker`, or **[Big list]** on the Drop tab, opens a large window with every item in a bag,
with one tab per bag: [All] [Inventory] [Satchel] [Sack] [Case] [Safe] [Safe 2] [Storage] [Locker] (Mog House bags only at home;
the Mog Wardrobes are never shown, because wardrobe gear is never dropped). Drop-list items in the Satchel, Sack and Case are brought into your
inventory and dropped (see below); Safe/Storage/Locker items drop once you move them into the inventory. Grouped by category and sorted A–Z in three columns.
Click an item to add it to the Drop list (it turns green); click a green item to remove it.
Adding an item drops the copies you're holding **after a 10-second cancel window**: the item shows a countdown
(`[9]`, `[8]`...) and clicking it again (or `//stw drop remove <item>`) cancels. **A second click within 5 seconds**
is needed first for gear, Rare/Ex, Keep-list items, currencies/seals/crests, quest items, anything an NPC won't
buy (usually Auction House goods), names Advice protects (upgrade materials), and any stack of 10 or more.
Loot of an item that has been on the Drop list for a while is still dropped as soon as it arrives.
**From other bags:** copies in your Satchel, Sack or Case are brought into the inventory one at a time and dropped:
when an item's 10-second window ends, and every 30 s while automatic sorting is on (`//stw start`). Never on load,
never from the wardrobes or Mog House bags, never Keep-list items, not when fewer than 2 inventory slots are free.
Turn it off with `//stw auto dropbags off` (or the switch on the Home tab). Drag the window by its title; mouse wheel pages.

## Zeni NM planner (Tinnin, Sarameya, Tyger)

`//stw znm [tinnin|sarameya|tyger]` or the **Zeni** tab: what you still need and the shortest way to get it.
It reads this character's seals and salts (key items) and the pop items / trophies in all bags, then lays out the
work as Sanraku visits (buy pops, trade trophies for seals) and hunting trips grouped by zone, one kill per NM.
Your other characters' Zeni items and seals are listed underneath (from their saved lists). Plans only: it never
buys, trades or moves anything. A seal is used up when it buys a pop item, and you hold one of each at a time.
**Fastest path** (default; `//stw znm cheap` / `fast` or the **[Fast]/[Cheap]** button): the planner tries every way of
picking the tier 1 / tier 2 NMs, repeats allowed, and keeps the one with the least estimated time (travel to each zone,
fights, Sanraku visits; zeni only breaks ties). So it may kill Vulpangue (next to Whitegate) three times instead of
travelling to Mamook and Alzadaal, which costs a little more zeni because buying the same pop again is dearer. Every pop
item and trophy is Rare/Ex, so one character holds one of each at a time; in team mode all three can each pop the same
NM in one trip. Times are rough estimates (Wajaom 3 min, Runic Portal zones 5-6, Mamook/Halvung/Aydeewa 8, 4 min a
fight, 4 min a Sanraku visit) and only used to compare plans.
**Team mode** (on by default; `//stw znm solo` / `//stw znm team` or the **[Team]** button switch it): pools all your
characters. Whoever is closest pops each final NM (shown as `Tinnin (CharC): ...`). Anyone's pop items and lower
seals are used (that character buys / pops it), trophies are lotted to whoever trades them next, and each step says who
does it (`CharB: Buy Oily Blood ...`, `CharB pops it, trophy to CharC`), with the zeni each character spends.
Tier 3 seals only count on the character who pops the final NM. Other characters' holdings come from their saved lists
(updated whenever they're logged in with Steward).
It also totals the **zeni** still needed for each NM and for all three: pop items at Sanraku's lowest prices (Tier 1
1,000, Tier 2 2,000, Tier 3 3,000; the final pop ~5,000 is an estimate) up to what it costs if each purchase in a row
raises the price (+100 / +200 / +300), plus 500 per salt (50 with "Rhapsody in Azure").

## AH prices in Advice (ffxiah.com)

`//stw prices` (or **[AH prices]** on the Advice tab) looks up the Advice SELL items that can go on the Auction House
on **ffxiah.com** for your server (Carbuncle; change with `//stw prices server <name>`). For each it keeps the median
of the recent sales and how many sell per week (single and stack). Advice then shows a **SELL on the Auction House**
section (median of at least 2,000 gil and at least 1 sale a week) and puts the price on every SELL row.
Prices are saved in `data/prices.lua` for all characters and reused for 3 days.
**Each page briefly freezes the game** (Windower can't fetch web pages in the background), so it only runs when you
ask, one page every 5 seconds; `//stw prices stop` or `//stw stop` stops it. Nothing is bought or sold.

## Sell list (with SellNPC)

The **Sell** tab works like the Drop tab (bag buttons, categories, orange = second click). Click an item to put it
on the Sell list: Steward queues it in the **SellNPC** addon (`//sellnpc <item>`), and the next time you open **any**
NPC shop SellNPC sells every copy in your **inventory**. Steward queues the list again after each shop visit, and
**[Load into SellNPC]** / `//stw sell load` queues it by hand (e.g. after logging in). Click an item on the left to take
it off (SellNPC is reloaded and the rest queued again). Needs SellNPC loaded: `//lua load sellnpc`.
Never on the list: Keep-list items, items NPCs won't buy, and anything in a Mog Wardrobe. Steward itself never sells.
Selling can't be undone, so check the list before opening a shop.

## Drop / Lot / Pass (Treasury-style)

Adding to the Drop list (any way: picker, tab, Advice or `//stw drop add`) waits 10 seconds before dropping what you
hold, so you can cancel (`drop_grace` in settings.xml changes the time).

On the **Drop**, **Lot** and **Pass** tabs, click a name on the left to remove it, or one of your items
on the right (Lot/Pass: inventory and treasure pool) to add it. Or type `//stw drop add Pebble`.
The **Drop** tab has a button per bag at the top: **[All] [Inventory] [Satchel] [Sack] [Case] [Safe] [Safe 2] [Storage]
[Locker]** (no wardrobes). The right column shows that bag (All = every bag but the wardrobes; Mog House bags only at home), and both
columns are grouped by category, A-Z, like the Big list. Gear, Rare/Ex, Keep-list and valuable-looking items are
orange and need a second click (shown with `?`).
An item can't be on the Lot list and the Pass/Drop lists at the same time.
Don't run Treasury at the same time, or both will act on the same items.

## Porter Moogle

The **Porter** tab lists slip-storable gear found **outside your wardrobes**. Click an item to skip
or include it. Stand next to a Porter Moogle and press **Store now** (or `//stw porter store`).
It gathers the items and their slips into your inventory and trades them slip by slip.
The slips go back to their home on the next sort.

* **Prep at home first**: `//stw porter prep` (or **[Prep inventory]** on the Porter tab) in your Mog House pulls the
  storable gear from Safe / Safe 2 / Storage / Locker / Satchel / Sack / Case and the slips it needs into your
  inventory. Whole slips are filled first; it keeps one slot free and tells you how many are left for another
  trip. Prepped items are held for 60 minutes so auto-sort and the free-slot goal don't put them back.
  Then walk to a Porter Moogle and press **Store now**. Whatever isn't stored is released afterwards.
* Never offered: anything in a wardrobe, wardrobe gear passing through your inventory, any item that also
  exists in a wardrobe, equipped items, and Keep-list items.
* Gear in your inventory is left out unless you turn on **Include inventory gear** on the Porter tab.
* Items in your Mog Safe etc. show "go home": store them at the Porter in your Mog Garden, or move them first.
* `//stw porter slips` lists, per slip, the storable gear you have (outside wardrobes) and whether you own that slip
  and where it is. Slips you don't own can be bought for 1,000 gil each from any Porter Moogle (Steward never buys
  anything); it tells you how many bag slots buying them would free. Advice's STORE list says "buy Slip NN first" too.
* **Buying slips**: `//stw porter buy` lists the slips your storable gear needs that you don't have, with the cost
  (1,000 gil each) and your gil. Nothing is bought until you stand next to a Porter Moogle and type
  `//stw porter buy confirm` (or `//stw porter buy 12 confirm` for one slip). It buys one slip at a time through the
  Porter's own menu, checks that exactly that slip arrived, and stops at the first surprise (wrong slip, nothing
  arrived, not enough gil, full inventory, Porter out of range) or on `//stw stop`. If a slip ever doesn't arrive,
  buy it by hand once: Steward remembers the menu option your game sent for that slip and uses it from then on.
  The menu details come from the LandSandBoat server project's Porter Moogle scripts; test the first purchase.
  Away from home (where the Mog Safe, Safe 2, Storage and Locker can't be read) both commands use the bag list
  Steward saved the last time you were in your Mog House, so gear stored there counts and slips kept there are never
  bought twice. If you haven't been home with Steward loaded yet, it says so.
* The Porter trade and menu handling is ported from **PorterPacker by Ivaar**.

## NPC storage

One command per kind of item an NPC keeps for you. Next to the NPC it trades everything of that kind,
batch after batch (pulling it out of Satchel/Sack/Case first). Anywhere else it **preps**: gathers the items
into your inventory and holds them there for 60 minutes so auto-sort leaves them alone.
The **NPC** tab shows counts (inventory / other bags / Mog House) with **[Prep]** and **[Store]** buttons;
the NPC's name turns green when you're in range.

| Command | Items | NPC |
|---|---|---|
| `//stw seals` | Beastmen's Seals, Kindred's Seals, Kindred's / High Kindred's / Sacred Kindred's Crests | Shami, Port Jeuno |
| `//stw crystals` | crystals and clusters (one element per trade) | Ephemeral Moogle |
| `//stw vouchers` | Copper Vouchers | Isakoth, Rolandienne, Fhelm Jobeizat or Eternal Flame |
| `//stw remstales` | Rem's Tale chapters 1-10 | Monisette, Port Jeuno |
| `//stw beastcoins` | Ancient Beastcoins | Sagheera, Port Jeuno |
| `//stw salvage` | Salvage plans (untested) | Mrohk Sahjuuli, Aht Urhgan Whitegate |
| `//stw soulplates` | Soul Plates for Zeni, one per trade (untested) | Sanraku, Aht Urhgan Whitegate |
| `//stw gobbiekeys` | SP Gobbie Keys, one per trade, ~14 s each; stops with under 2 free inventory slots (each key gives a prize) | Mystrix or any Gobbie Mystery Box goblin |
| `//stw moatcarp` | Moat Carp | Joulet / Gallijaux, Port San d'Oria |
| `//stw mellidopt` | Mellidopt Wings (untested) | the ??? that takes them |
| `//stw alexandrite` | Alexandrite | Paparoon |
| `//stw zinc` / `//stw yagudo` | Zinc Ore / Yagudo Necklaces, exactly 4 a trade | Talib (Port Bastok) / Nanaa Mihgo (Windurst Woods) |
| `//stw mandragora` | Mandragora Mad items, one a trade (inventory only) | Yoran-Oran, Windurst Walls |
| `//stw onlybest` | Only the Best: 5 cabbage, else 3 millioncorn, else 1 moss | Melyon |
| `//stw jsecapes` / `//stw jsecapes3` | JSE capes one a trade / 3 alike (inventory only, never wardrobes) | A.M.A.N. Reclaimer / Makel-Pakel |
| `//stw stones` | Reisenjima stones | Oseem |
| `//stw befouled` | Befouled Water (one trade) | Odyssean Passage |
| `//stw geaszitah` / `geasruaun` / `geasreis` | Geas Fete pop items: one set, skipping pops whose key item you hold (inventory only) | Affi / Dremi / Shiftrix |

`//stw trade` (or `//stw qtr`, or **[Trade with NPC here]** on the NPC tab) works like QuickTrade's `//qtr`: it trades
with whichever of these NPCs you're targeting or standing next to. Crystals also go to any **Waypoint** (all elements in
one trade). Everything QuickTrade did is covered, so QuickTrade doesn't need to be loaded.

Add `prep`, `store` or `list` to choose, e.g. `//stw seals prep` at home, then `//stw seals` at Shami.
`//stw npc` lists what you have of every type. Stand still (idle) while it trades; it stops if the NPC
doesn't take an item or you walk away, and `//stw stop` stops it. The NPC's dialogue is skipped for 10 seconds
after each trade. Wardrobes and Keep-list items are never touched.
Item lists and trade waits come from **QuickTrade by Valok@Asura**; the trade request format is
**TradeNPC by Ivaar** (neither needs to be installed).

## Commands

```
//stw                       show / hide the window
//stw start                 turn automatic sorting on (off at every load)
//stw sort [bags|wardrobes] sort once now
//stw stop                  stop sorting/storing/trading, automatic sorting off
//stw picker                big clickable item list for the Drop list
//stw goal <n>              keep n inventory slots free (0 = off, default 70)
//stw advice                next steps: what to sell, toss or store
//stw advice ignore add|remove <item>   never suggest this item
//stw sellprep | unhold     gather sell items (holds auto-sort 10 min) | end the hold
//stw resume                resume automation after a safety pause
//stw log [on|off]           activity log (shows where the file is)
//stw keep|drop|lot|pass add|remove <item>
//stw keep|drop|lot|pass list
//stw rule <category> <bag>     e.g. //stw rule crystals satchel
//stw overflow <category> <2nd> [3rd]   where it goes when its bag is full, e.g. //stw overflow crystals case satchel
//stw overflow <category> auto          back to the automatic 2nd/3rd bags
//stw wardrobe <group> <1-8>    e.g. //stw wardrobe accessories 7   (0 = automatic)
//stw auto <sort|wardrobes|drop|lotpass|stack> [on|off]
//stw porter prep           (at home) gather storable gear + slips into the inventory
//stw porter list|store
//stw porter slips          slips you have / would need to buy
//stw porter buy [nn] [confirm]   buy the slips Advice needs (1,000 gil each) at a Porter Moogle
//stw npc                   what you have for each NPC
//stw seals|crystals|vouchers|remstales|beastcoins|salvage|soulplates|gobbiekeys [prep|store|list]
//stw audit [job|all]       GearSwap files vs wardrobes: missing / unused gear
//stw find <text>           search all bags of all your characters (find alone: saved characters)
//stw merge [on|off]        list split stacks across bags (merged on every sort)
//stw stack | verbose | delay <seconds>
```

Moves use the same item-move requests as Organizer and Treasury, one at a time with a 0.6 s gap
(`//stw delay` to change it).
