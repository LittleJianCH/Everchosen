# Everchosen: Agent Instructions

## Repository and product boundaries

This repository contains Total War: WARHAMMER III mods. The earlier prototype workspace, referred to below as `../Everchosen/`, is technical reference material and not part of this repository. Do not import its implementation wholesale; when it is absent from a checkout, do not guess at its contents.

| Product | Source directory |
| --- | --- |
| **Archaon: The Everchosen** — main mod | `mods/archaon-everchosen/` |
| **Tamurkhan Chieftain Progression** — separate submod | `mods/tamurkhan-chieftains/` |
| **Chaos Equipment for Warriors of Chaos** — separate submod | `mods/chaos-equipment/` |

- Equipment eligibility covers Khorne, Nurgle, Tzeentch, Slaanesh, Norsca, Beastmen, and Chaos Dwarfs, and adds Warriors of Chaos culture eligibility for weapons, armour, talismans, enchanted/arcane items, and mounts. Preserve native access and character/skill/rank restrictions; do not grant items or bypass acquisition quests. Keep this data patch out of the other products.
- Keep all other gameplay in the main mod, including blessings, subjugation, portals, Beastmen hordes, and Norscan outposts. Split out another submod only when the user explicitly selects it; future submods stay in this repository.
- Give each product distinct build outputs and packaging boundaries. A separate submod does not by itself imply a dependency on the main mod. Define dependencies and coexistence when implementing them, and prevent duplicate listeners or rewards when both packs are loaded.
- Equipment eligibility and chieftain progression are independently loadable. Enable the equipment submod alongside progression when chieftains in Warriors of Chaos need their native equipment permissions; do not duplicate the permission patch in progression.
- Share helpers when needed, without duplicating gameplay or building a general framework ahead of requirements.
- Do not add a README unless requested.
- Do not record development progress, completion status, task checklists, session summaries, handoff notes, or temporary next steps in repository files, including documentation and code comments. Keep progress reports in the conversation. Repository guidance should describe durable rules, design decisions, usage contracts, and technical evidence with its limits.

## Player-facing feature guide

- Keep `docs/features.md` in sync when adding, changing, or removing player-visible features, activation conditions, configuration, dependencies, or compatibility requirements.
- This document is for players. Write in Chinese and explain available gameplay, how to use it, and necessary usage or compatibility conditions. Use the game's Chinese localization for character and mechanic names; list supported characters explicitly rather than using vague examples.
- Describe only current features. Do not add unimplemented features, roadmaps, development progress, or lists of what has not been done.
- Keep implementation details out of this guide, including source languages, internal keys, APIs, database structure, generators, build and packaging steps, debugging history, test results, and validation reports. Keep development and verification discussion in the conversation; do not turn the guide into a developer handoff or claim unobserved in-game verification.

## Fresh-save policy

- All mod feature design, implementation, fixes, and validation must assume a brand-new save (a new campaign) created with the current mod version.
- Compatibility, migration, or repair of saves affected by incorrect mods, defective older mod versions, or erroneous mod operations is out of scope, including their residual state.
- Do not add compatibility branches, historical data migrations, state compensation, or save-repair logic for those saves. Fix the implementation so that behavior is correct in new saves.
- Reproduction and acceptance must use new saves. Whether an affected old save can recover or remain playable is not a requirement.

Normal saving and loading within a campaign created with the current version remains required: preserve intended progression, cooldowns, and once-per-turn decisions. Historical documents recommending old-save repair or migration do not override this policy.

## Implementation and toolchain

- Write new campaign logic in **Fennel**, compile ahead of time to **Lua 5.1-compatible source**, and package the generated Lua with DB, localization, and UI assets. Players must not need Fennel or development dependencies.
- Use WSL 2 Ubuntu with a normal user account. The Lua 5.1 dependency tree is `~/.local/share/everchosen/lua51`; activate it with `source tools/wsl/activate.sh`. Setup/check scripts and pinned dependency versions are maintained in `tools/wsl/`. Build the mods with `tools/build.ps1` from PowerShell or `bash tools/wsl/build.sh` from WSL; this stages pack contents without creating or installing a `.pack`. Check relevant tools before changing the environment; do not reinstall it by default.
- Package in PowerShell 7 with `tools/package.ps1 -Mod <product> -Rpfm <exe> -Schema <ron>`, adding `-GameData <game data directory>` for the main mod and equipment. The equivalent path variables are `RPFM_CLI`, `WH3_SCHEMA`, and `WH3_DATA`. Packaging extracts native inputs into a disposable local directory, stages each product separately, encodes DB/Loc TSVs, verifies pack contents, and writes `.pack` files to `dist/` without installing them. For staging generated assets alone, pass `-VanillaDb <extraction root>` to `tools/build.ps1` or set `EVERCHOSEN_VANILLA_DB` in WSL (default `.local/vanilla`).
- Author DB rows and localization whose content does not depend on native data as TSVs under `mods/<product>/assets/`. An authored TSV pins its column layout and table version, so following a game update that changes either is a manual edit; a generator that reads the same native table reports the mismatch through `read_authored`.
- Generate only what follows native data: rows cloned or selected from native records, adapted native UI, and lists the campaign script needs from those records. Keep each product's generator in `mods/<product>/generator/generate.py`, with its rules and native-input list defined directly in Python and its fragments named apart from the authored ones. State plain copies of native rows as data tables at the top of the generator, and write a function only for a derivation that needs a lookup or a check. Expose the input list through `--print-inputs` for packaging. Share TSV reading, validation, writing, stable ID derivation, and the command-line contract through `tools/db_tables.py`; keep gameplay-specific selection and UI transformations with their product.
- Keep authored source separate from generated Lua and `.pack` output. Edit source and rebuild. Use UTF-8 and LF, and handle Windows/WSL paths explicitly.
- Validate emitted syntax with Lua 5.1. Fennel compilation alone does not establish runtime library or game API availability. Declare expected WH3 globals explicitly in the `--globals` list in `tools/wsl/build.sh`, and reach optional globals such as MCT's through `_G`; use the game's loader, paths, and load order rather than relying on desktop LuaRocks search paths.
- Keep per-mod Fennel helpers in `lib/` and use namespaced `include` modules to bundle them into the Lua entry points. Helpers must not become separate campaign auto-load scripts.
- Prefer small modules with explicit dependencies. Separate pure rules from game-event adapters where that makes the implementation easier to reason about. In `tamurkhan-chieftains`, `data` holds keys and defaults, `rules` is pure, `world` queries the campaign model, `settings` and `mct` handle configuration, and `campaign` owns listeners and commands.
- Preserve original game packs and Workshop inputs; extract references for inspection. Do not commit proprietary dumps or credentials. Check redistribution permission before publishing reused assets or code.
- When installing a requested build, confirm the game is closed, retain an appropriate previous artifact, and verify the installed pack matches the build. A build request alone is not a publishing request.

## Fennel style

Follow the [Fennel style guide](https://fennel-lang.org/style). The rules below are the ones this codebase has needed; they describe idiomatic Fennel, not Lua transliterated into parentheses.

- **Bindings.** Use `local` for top-level definitions and `let` inside functions. Use `var` only for state that really changes, keep it close to its use, and say in a comment what it guards.
- **Building values.** Use `collect`, `icollect`, `fcollect`, and `accumulate` (with `&until` for an early exit) instead of a `var` or empty table mutated from an `each` loop.
- **Conditionals.** `if` returns a value; `when` is for side effects. Rely on `nil`/`false` being falsy, as in `(or value fallback)`, instead of comparing against both, unless `false` is a meaningful value.
- **Method and field access.** Write `(object:method)` and `table.field`. Use `(: expression :method)` and `(. table key)` only when the receiver is not a symbol or the key is computed. Use `(set table.field value)` for literal keys and `tset` for computed ones. When a call chain or a compound condition repeats, name it once in a helper such as `world.ours?`.
- **Game lists.** List interfaces are zero-indexed `num_items`/`item_at` objects. Iterate them with `world.items` instead of hand-written index loops.
- **Names.** Use kebab-case, with a `?` suffix for predicates and boolean flags. Use `:keyword` strings for opaque keys and quoted strings for player-facing text and anything that is concatenated.
- **Functions.** Define functions at the top level of a module instead of nesting them in one long closure; keep module state in top-level `var`s. Mutual recursion gets one forward-declared `var` with a comment. Pass a named function and its arguments to `pcall` instead of wrapping an anonymous closure. Keep `#(...)` for single-expression callbacks.
- **Shared constants.** Define keys, limits, and option names once (`data.fnl`, or a helper such as `rules.level-key`) and reference them from every module that needs them.
- **Modules.** End each module with its export table. Give exported functions a docstring when the argument or return contract is not obvious from the name.
- **Comments and layout.** Use `;;;` for section headings and `;;` for comments that explain why. Keep lines within 80 columns, except for player-facing text literals.

## Proportionate verification

- **Do not create excessive, meaningless tests or test merely for testing's sake.** Choose checks that address a concrete failure risk or demonstrate required behavior. Documentation and other reversible, low-impact edits do not automatically need tests.
- A behavior-preserving refactor is checked by comparing the old and new builds against the same scripted inputs; that comparison is disposable and does not belong in the repository.
- Prefer a focused regression that exposes a real bug over large matrices of equivalent cases. Test observable outcomes; avoid repeating implementation logic, brittle source-string assertions, trivial constant checks, redundant snapshots, or mocks that predetermine success.
- Run gameplay tests under Lua 5.1, using Busted where useful. Ground small game-interface mocks in native scripts or API evidence; do not recreate the engine. Python is suitable for data/resource validation and packaging, but should not become the default gameplay-test host or contain large embedded Lua test programs.
- Check actual DB references and unintended scope changes. For engine-dependent behavior, use a focused new-campaign observation instead of expanding invented mocks. Include controls for unrelated actors when shared data or UI could affect them.
- Run relevant checks after changes; repeat or broaden only for new changes, failures, or unresolved concerns. These technical notes are reference material, not an exhaustive checklist for every task.
- Report the evidence accurately: compilation, static/data validation, mocked logic, pack round-trips, and in-game observations establish different things. State remaining limits instead of claiming an unobserved gameplay result.

## Reading the technical notes

The notes below summarize technical evidence from WH3 **9.0.1–9.0.3**. Treat that version scope as a limit on the evidence, not a declaration of supported game versions or features.

- **Native evidence** means a relevant game script, DB record, or UI definition was inspected. It establishes that source fact for its recorded version, not every engine consequence.
- **Historical observation** means a result was reported or observed in an earlier prototype. Preserve its limits; a proposed or statically checked fix is not an in-game success.

For the feature being changed, inspect current native records before using keys, scopes, events, or APIs. Record the relevant game/schema baseline where it matters. Earlier extractions left some DB files undecoded despite a successful tool exit, so check support for the actual tables used. Historical locks, balance values, feature counts, and temporary UI coordinates do not establish product requirements.

## WH3 reference notes

### Database and packaging

- Internal pack paths and DB fragment names affect loading and overrides. Use paths the game recognizes and an RPFM schema supporting the changed tables, including their field order, types, versions, and references.
- **Historical observation:** a pack round-tripped successfully but crashed on an invalid `campaign_effect_scopes` reference, `force_to_force_own_unseen`. Serialization does not prove DB validity; even display-only effects need real references.
- **Native/pack evidence:** a differently named fragment does not delete a vanilla row. Replace a vanilla fragment only deliberately, preserving unrelated records.
- Use namespaced keys and narrow permissions. Player-only Lua guards cannot isolate shared culture, faction-set, force-type, or UI overrides.
- **Historical observation:** a faction-specific building-availability set omitted vanilla Warriors of Chaos chains, and settlement conversion failed. Do not assume such a set augments the default: preserve the applicable base list and compose permissions across modules. Competing outpost and horde selection rules caused a similar conflict.

### Campaign ownership and events

- **Native evidence:** the campaign localization interface used by inspected scripts is `common.get_localised_string`. The outpost prototype's assumed `effect` global failed in-game; a permissive mock had hidden the mistake.
- `pcall` success establishes absence of a Lua exception, not completion of an engine action. For APIs without a reliable result, confirm the resulting object, ownership, or completion event.
- Guard null interfaces and re-query ownership after transfers or asynchronous callbacks. Include wounded characters when checking actual ownership; an unlocked unique-agent registry entry alone is insufficient.
- Make progression, rewards, and resource changes safe against duplicate events and ordinary save/load. Keep persistent progression separate from temporary in-flight command guards.
- **Historical scope:** the main prototype targeted player-controlled Archaon (`wh_main_chs_chaos`) in single-player Immortal Empires (`main_warhammer`). Do not silently infer support for other hosts or campaigns; keep data and UI scope aligned with the intended script scope.
- Preserve requested acquisition paths. Do not substitute direct grants for natural recruitment, progression, or quests unless granting is the intended design.

### Subjugation and inherited mechanics

- **Native evidence:** confederation, vassalization, and lord transfer are distinct. Archaon's subjugation can transfer the lord while merging the source faction into a proxy vassal. `ScriptEventArchaonSubjugatesChaosFaction` and `archaon_subjugation_config` are integration points; check actual host ownership before unlocking rewards.
- **Historical lesson:** establish a valid remaining faction leader before transferring the last relevant leader. An ordinary army does not prove a valid faction-leader reference. Inspect native challenge/post-battle cleanup before extending target lists: some paths destroy armies and can conflict with persistent vassals.
- Classify god allegiance from verified subcultures and explicit exceptions. Scope vassal effects to the intended relationship and remove only this mod's contribution when it ends.
- **Native evidence:** inherited mechanics require more than visible buttons. Plagues have faction initialization, symptom progression, resources, and friendly/hostile effects; portals have permissions, nodes, and a source of uses. Be'lakor's portal network and Tzeentch's teleport stance are distinct; opening a provincial node does not place it beneath the lord.

### Hordes, buildings, and recruitment

- **Native evidence:** Beastmen legendary lords use `HORDE_KHAZRAK`, `HORDE_MALAGOR`, `HORDE_MORGHUR`, and `HORDE_TAUROX`. **Historical observation:** one Taurox confederation experiment preserved identity, camp, and growth through a reload and one turn. It did not validate battle subjugation, army destruction, wounded recovery, construction, or recruitment.
- Building adaptation can involve chains/superchains, instances, slots, availability, culture variants, categories, upgrade links, effects, localization, and display mappings. Follow relevant relationships rather than cloning an isolated row.
- **Historical observations:** missing category links coincided with empty construction menus; missing `campaign_settlement_display_building_ids` links were found when encamped models disappeared. Culture-gated stance visuals also needed adaptation after transfer. Finding a missing relationship does not establish that adding it fixes the engine behavior.
- Shared force types or slot templates can change original-faction behavior. Preserve native access, keep custom horde chains out of settlement slots, and configure starting buildings for newly created forces rather than reconstructing affected old camps.
- Building access, unit permissions, UI, recruitment source, stock, and caps are separate constraints. **Native evidence:** Warriors of Chaos have `DISABLE_DEFAULT_RECRUITMENT`; showing a button did not unlock recruitment. A provincial warband pool is a distinct recruitment source; enabling UI or supplying pool records alone does not prove that recruitment works.
- **Native evidence:** inspected building-recruitment rows used an empty faction with `enabled=false` for unqualified entries and `enabled=true` for faction-qualified entries. Recheck the convention before copying rows across scopes.
- Distinguish stock, capacity, and recruitment-source limits. Where supported, use module-specific capacity contributions, deduplicate same-province/unit refreshes, and remove only the owning mechanic's contribution. A large `unit_cap` bonus is not unlimited capacity; avoid changing shared `main_units` caps for a faction-specific need.
- Do not infer how daemon caps count units from alternative recruitment sources after transfer/merge, or how stock contracts, without engine evidence. Scripted refresh chances may differ from native unit-card percentages; do not fabricate UI values to imply equivalence.

### Outposts, UI, and equipment

- **Historical prototype:** Norscan outposts used `UNDERDEEP` foreign slots while the vassal retained the settlement. Runtime slot creation left the main building empty. Initialize it explicitly and confirm success before charging; identify slots by template, not list order.
- Establish an outpost only through an explicit player action. Recheck current ownership, vassalage, army presence, turn, funds, and existing slots when it executes. Selection, movement, hovering, and panel opening must not create buildings or charge money.
- Remove only the module's supply/capacity when eligibility ends; never delete a whole foreign-slot manager containing another mechanic's buildings. Slot creation alone does not establish construction, upgrade, recruitment, or stock-contraction behavior.
- Use a private panel when a shared view targets or labels the wrong mechanic. Preserve native clicks, cooldowns, tooltips, and selection refreshes; use actual layout bounds/anchors and concise player-facing descriptions.
- **Historical observation:** a shared portal-character whitelist unintentionally restricted Be'lakor's original faction. Scope permissions to the actor's current faction and intended network. UI restrictions govern those actions, not automatically AI or direct script commands.
- **Historical observation:** broad live UI/Cco traversal preceded a crash, but this does not establish causation. Use narrow, guarded diagnostics; do not treat the old traversal as a proven diagnosis or repeat it as a routine check.
- **Native evidence:** faction-set, character, skill, and rank restrictions on equipment are independent; skill-tree display and faction eligibility are also separate from character progression. Preserve native eligibility and mount unlock gates. Inspect native quest registration: permission to equip does not prove the item can be acquired.
- **Historical prototype:** Tamurkhan's progression used his rank to determine a target count of owned chieftains, included wounded heroes, and added only missing ones. Its separate equipment patch changed faction permissions without changing skill/rank gates. That static patch did not verify acquisition or mount unlocking, and it is not the progression feature itself.

## Earlier evidence to consult when relevant

Consult these references for relevant technical evidence. They are not task lists or specifications for what to implement.

| Reference | Useful evidence and limits |
| --- | --- |
| `../Everchosen/docs/WOC-demo-说明.md` | Mechanic integration and failure analysis; distinguish static checks from in-game evidence. |
| `../Everchosen/docs/norsca-outpost-prototype.md` | Foreign-slot initialization, localization API, private UI, and building-availability conflicts. |
| `../Everchosen/docs/G03-陶诺斯营地实测-01.md` | The limited Taurox transfer/reload/growth observation and what it did not establish. |
| `../Everchosen/docs/可行性复核-第一轮.md`, `../Everchosen/reference.lock.json` | Source/schema provenance and feasibility evidence. |
| `../Everchosen/tests/chieftains-diagnosis/diagnosis.json`, `../Everchosen/tests/chieftains-equipment-fix/verification.json` | Equipment restrictions and the limits of the static permission fix. |
| `../Everchosen/references/` | Extracted native evidence for local inspection; not repository content. |
| `tools/wsl/` | Environment setup, pinned dependencies, and compilation/test checks. |
