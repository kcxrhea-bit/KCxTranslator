KCxTranslator

KCxTranslator is a Blizzard-safe World of Warcraft translation addon focused on helping players communicate across languages without automation, memory reading, or external gameplay control.

Built for WoW TBC Classic and designed around manual-only workflows, KCxTranslator provides lightweight English ↔ Spanish translation tools directly inside the game using local Lua dictionaries and contextual phrase handling.


---

Features

Manual Translation Commands

Translate text safely using slash commands:

/kcxt <text>
/kcxtsay <text>

Examples:

/kcxt hello how are you
/kcxtsay necesito healer para dungeon


---

Blizzard-Safe Design

KCxTranslator does not:

automate gameplay

read game memory

inject packets

control characters

auto-send translated chat

use external executables


Everything is manual and user-triggered.


---

Local Dictionary Translation

Translation logic is handled locally using Lua dictionaries and phrase systems.

Current dictionary categories include:

everyday phrases

raids

dungeons

PvP

professions

classes

social/chat slang

role terminology



---

Smart Translation Features

Contextual Phrase Assembly

KCxTranslator attempts:

exact phrase matches first

contextual phrase grouping

fallback word translation

shorthand normalization

dungeon/role phrase handling


This improves readability compared to simple word-for-word translation.


---

Incoming Translation Support

Incoming messages can be translated into readable conversational output while preserving important WoW formatting.

Protected systems include:

item links

URLs

guild tags

bracketed game text

channel formatting



---

Public Channel Safety Filtering

For channels like:

Trade

General

LookingForGroup

Services


KCxTranslator only translates detected Spanish-like segments instead of rewriting entire messages.

This keeps:

English text intact

channel readability stable

spam low

translations safer and cleaner



---

Translator Window

KCxTranslator includes an in-game translator UI with:

translation history

copy/highlight support

incoming translation toggle

channel filtering

debug tools

test tools

stats display

minimap access


Buttons currently include:

Incoming ON/OFF

Clear

Copy Last

Stats

Test

Channels



---

Philosophy

KCxTranslator was built around a simple idea:

> Help players communicate across languages without breaking Blizzard rules.



The addon focuses on:

accessibility

manual control

local-first logic

lightweight performance

practical in-game communication



---

Installation

1. Download the repository


2. Extract the folder


3. Place it inside:



World of Warcraft/_classic_/Interface/AddOns/

4. Launch WoW


5. Enable KCxTranslator in the AddOns menu




---

Example Commands

/kcxt hello friends
/kcxt necesito tanque y healer
/kcxtsay looking for group
/kcxt copylast
/kcxt incoming on
/kcxt channels


---

Current Status

KCxTranslator is an actively developed experimental addon.

Current development areas:

smarter contextual translation

improved phrase handling

expanded dictionaries

incoming translation refinement

UI polish

conversational filtering

bidirectional improvements



---

Roadmap

Planned future improvements include:

confidence indicators

better conversational reconstruction

expanded multilingual support

optional translation export tools

cleaner chat categorization

enhanced UI/UX polish



---

Repository Goals

This project is also part of a larger KCx Labs portfolio focused on:

local-first software

AI-assisted development workflows

privacy-first tooling

practical utility software

iterative systems engineering



---

License

This project is provided for educational and personal use.

World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc.

KCxTranslator is an independent fan-made addon and is not affiliated with or endorsed by Blizzard Entertainment.


---

Developer

KCx / KCx Labs

GitHub:

https://github.com/kcxrhea-bit
