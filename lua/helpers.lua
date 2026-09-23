-----------------------------------------------------------------------------
-- General helper methods for bot functionality
-- Author: wyanido, storyzealot
-- Homepage: https://github.com/wyanido/pokebot-nds
-----------------------------------------------------------------------------

--- Attempts to re-read the party data from memory and update the global reference 
function update_party()
    -- Don't attempt to read the party before a save is loaded.
    -- Notably it can still be read at this point in gen 4, but
    -- this is ignored to keep it consistent across all games.
    if not game_state.in_game then
        local party_was_emptied = #party ~= 0

        party = {}
        
        return party_was_emptied
    end

    local party_size = mbyte(pointers.party_count)
    local party_was_updated = false

    for i = 1, 6 do
        local checksum = mword(pointers.party_data + 6 + _MON_BYTE_LENGTH * (i - 1))
        
        if i <= party_size then
            if party[i] == nil or checksum ~= party[i].checksum then -- If the Pokemon has changed, re-read its data
                local mon_data = pokemon.read_data(pointers.party_data + (i - 1) * _MON_BYTE_LENGTH)

                if mon_data then
                    local mon = pokemon.parse_data(mon_data, true)
                    
                    party[i] = mon
                    party_was_updated = true
                else
                    print_debug("Party checksum failed at slot " .. i)
                end
            end
        else
            if party[i] ~= nil then
                party_was_updated = true
                party[i] = nil
            end
        end
    end
    
    return party_was_updated
end

--- Attempts to read the foe(s) data from memory
function update_foes()
    -- Make sure a battle is actually underway before reading
    local battle_value = mbyte(pointers.battle_indicator)

    if not game_state.in_game or (battle_value ~= 0x41 and battle_value ~= 0x97 and battle_value ~= 0xC0) then
        foe = nil
        return
    end

    -- If the foe is already known, then don't re-read it within the same battle
    if foe then
        return
    end

    local function attempt_fetch()
        local foe_count = mbyte(pointers.foe_count)
        
        if foe_count == 0 then
            print_debug("Foe data doesn't exist yet, retrying next frame...")
            return
        end

        local foe_table = {}

        for i = 1, foe_count do
            local mon_data = pokemon.read_data(pointers.current_foe + (i - 1) * _MON_BYTE_LENGTH)
            
            if mon_data then
                local mon = pokemon.parse_data(mon_data, true)
                
                table.insert(foe_table, mon)
            else
                print_debug("Foe checksum failed at slot " .. i .. ", retrying next frame...")
                return
            end
        end

        foe = foe_table
    end

    -- Attempt to identify the foe once per frame until it succeeds
    while foe == nil do
        -- Exit in case the bot SR'ed during this stage
        if not game_state.in_game then
            return
        end

        attempt_fetch()
        emu.frameadvance()
    end
end

--- Converts an unsigned 32-bit int to a signed 16-bit int
local function to_s16(u32)
    return ((u32 / 65536) + 32768) % 65536 - 32768
end

--- Updates the global reference of the current game state for bot modes to use
function update_game_state()
    if pointers.map_header < 0 then
        game_state = {}
        return
    end
    
    local map = mword(pointers.map_header)
    local save_is_loaded = _MAP[map] ~= nil

    -- Don't consider the save file as 'loaded' if the Journal page is open
    if _ROM.version == "D" or _ROM.version == "P" or _ROM.version == "PL" then
        save_is_loaded = save_is_loaded and mdword(pointers.start_value) ~= 0
    end

    if not save_is_loaded then
        game_state = {}
        return
    end

    game_state = {
        in_game = true,
        in_battle = type(foe) == "table" and #foe > 0,
        map_header = map,
        map_name = _MAP[map + 1],
        trainer_name = read_string(pointers.trainer_name),
        trainer_id = string.format("%05d", mword(pointers.trainer_id)) .. " (" .. string.format("%05d", mword(pointers.trainer_id + 2)) .. ")",
        trainer_x = to_s16(mdword(pointers.trainer_x)),
        trainer_y = to_s16(mdword(pointers.trainer_y)),
        trainer_z = to_s16(mdword(pointers.trainer_z)),
    }

    if _ROM.gen == 5 then
        game_state["phenomenon_x"] = mword(pointers.phenomenon_x + 2)
        game_state["phenomenon_z"] = mword(pointers.phenomenon_z + 2)
    end
end

--- Returns whether a table contains a given string key
function table_contains(table_, item)
    if type(table_) ~= "table" then
        table_ = {table_}
    end

    for _, table_item in ipairs(table_) do
        if string.lower(table_item) == string.lower(item) then
            return true
        end
    end

    return false
end

function abort(reason)
    if _EMU == "BizHawk" then
        client.invisibleemulation(false)
    end
    
    clear_all_inputs()
    print("##### BOT TASK ENDED #####")
    error(reason)
end

function cycle_starter_choice()
    if starter == nil then starter = -1 end
    
    -- Alternate between starters specified in config and reset until one is a target
    if not config.starter0 and not config.starter1 and not config.starter2 then
        abort("At least one starter selection must be enabled in config for this bot mode")
    end

    -- Cycle to next enabled starter
    starter = (starter + 1) % 3

    while not config["starter" .. tostring(starter)] do
        starter = (starter + 1) % 3
    end

    return starter
end

--- Advances the game by one frame and calls all update methods
-- All frame advances go through this method, meaning it can
-- update the current game state without needing asynchronosity
function process_frame()
    if config.focus_mode and _EMU == "DeSmuME" then
        emu.emulateframeinvisible()
        sound.clear()
    else
        if _EMU == "BizHawk" then
            client.invisibleemulation(config.focus_mode)
        end

        emu.frameadvance()
    end
    
    decrement_input_buffers()
    update_pointers()
    update_game_state()
    update_foes()
    
    -- Only send data on change to minimize expensive DOM updates on dashboard
    local party_was_updated = update_party()
    
    if party_was_updated then
        print_debug("Party updated")
        dashboard_send({
            type = "party",
            data = party
        })
    end

    -- Interact with the dashboard once per in-game second
    if emu.framecount() % 60 == 0 then
        dashboard_send({
            type = "game_state",
            data = game_state
        })
        
        dashboard_poll()
    end
end

--- Returns an array of booleans to indicate the egg state for each party member
function get_party_egg_states()
    local eggs = {}

    for i = 1, 6 do
        -- IMPORTANT: an empty party slot is nil, NOT an Egg.  Treating an
        -- empty slot as true makes nil -> Pokemon look exactly like an
        -- Egg -> Pokemon transition, which can queue existing party members
        -- for PC deposit.
        if party[i] then
            eggs[i] = party[i].isEgg == true
        else
            eggs[i] = nil
        end
    end

    return eggs
end

--- Handles the D/P/Pt egg hatch transition.
--
-- Do NOT rely on update_party() alone here. update_party() deliberately caches
-- party entries and only reparses them when the checksum changes. During the
-- actual hatch transition the game can update the party structure while the
-- checksum/cache timing is not yet reflected in that cached table. For this
-- reason the hatch detector explicitly reads the six live party structures
-- from emulator memory on every check and parses them with the normal Gen IV
-- decryption/checksum code.
function check_hatching_eggs(current_stuck_frames)
    -- move_to() invokes this callback without arguments. In that path there is
    -- no local movement-stall counter, so treat the missing value as zero.
    -- The DPPt hatching loop passes its real stuck_frames value explicitly.
    current_stuck_frames = tonumber(current_stuck_frames) or 0
    if _ROM.version == "HG" or _ROM.version == "SS" then
        if emu.framecount() % 10 == 0 then
            press_button_async("B")
        end
    end

    -- D/P/Pt hatch trigger:
    -- Do NOT use the Egg-cycle value as the trigger.  In practice that value
    -- does not give us a reliable frame-accurate indication of when the game
    -- has actually presented the "Oh?" prompt.
    --
    -- The hatching route already detects when the trainer stops moving.  When
    -- an Egg is present, use that existing stopped-movement state as the point
    -- at which to send A.  The Egg -> Pokémon transition is then used ONLY as
    -- post-hatch verification.
    --
    -- 60 frames = 1 second.  This is deliberately below the normal 180-frame
    -- movement watchdog so a ready Egg gets the first opportunity to consume
    -- the "Oh?" prompt instead of the route reversing direction.
    local HATCH_STOP_FRAMES = 30

    local party_size = mbyte(pointers.party_count)
    local egg_slot = nil
    local egg_pid = nil

    for i = 2, 6 do
        if i <= party_size then
            local address = pointers.party_data + (i - 1) * _MON_BYTE_LENGTH
            local mon_data = pokemon.read_data(address)
            if mon_data then
                local mon = pokemon.parse_data(mon_data, true)
                party[i] = mon

                if mon.isEgg == true then
                    egg_slot = i
                    egg_pid = mon.pid
                    break
                end
            end
        end
    end

    if egg_slot == nil then
        party_egg_states = get_party_egg_states()
        return false, nil
    end

    -- Only trigger from the existing movement-stall signal.  We do not inspect
    -- or depend on the Egg-cycle counter here.
    if current_stuck_frames >= HATCH_STOP_FRAMES then
        clear_all_inputs()

        print_debug("DPPt egg present and trainer stopped for " ..
            tostring(current_stuck_frames) .. " frames; pressing A for hatch prompt" ..
            " slot=" .. tostring(egg_slot) .. " PID=" .. tostring(egg_pid))

        hatch_egg(egg_slot)
        process_frame()

        -- hatch_egg() returns only after the live party slot has been observed
        -- as a non-Egg.  This is verification, not the trigger.
        local address = pointers.party_data + (egg_slot - 1) * _MON_BYTE_LENGTH
        local mon_data = pokemon.read_data(address)

        if mon_data then
            local hatched = pokemon.parse_data(mon_data, true)
            party[egg_slot] = hatched

            if hatched and not hatched.isEgg then
                local is_target = pokemon.log_encounter(hatched)
                if is_target then
                    abort("Hatched a target Pokémon: " .. hatched.name .. "!")
                end

                wait_frames(90)
                party_egg_states = get_party_egg_states()
                print_debug("Confirmed newly hatched Pokémon: " .. tostring(hatched.name) ..
                    " slot=" .. tostring(egg_slot) .. " pid=" .. tostring(hatched.pid))
                return true, egg_slot
            end

            print_warn("Hatch sequence finished, but slot " .. tostring(egg_slot) ..
                " is still an Egg; no PC deposit queued.")
        else
            print_warn("Could not re-read party slot " .. tostring(egg_slot) ..
                " after the hatch sequence.")
        end
    end

    party_egg_states = get_party_egg_states()
    return false, nil
end



--- Read-only diagnostic for locating the live Gen IV PCBoxes structure in RAM.
-- Platinum defines PCBoxes as 18 boxes x 30 BoxPokemon records, with a
-- currentBoxID u32 immediately before the 540 records. Each BoxPokemon is
-- 0x88 bytes. We validate real encrypted BoxPokemon checksums rather than
-- treating arbitrary RAM as PC data.
function scan_pc_boxes_ram()
    if pointers and pointers.pc_boxes then
        return pointers.pc_boxes
    end

    local RAM_START = 0x02000000
    local RAM_END = 0x02400000
    local SLOT_SIZE = 0x88
    local TOTAL_SLOTS = 18 * 30
    local PARTY_SAVE_OFFSET = 0xA0
    local PARTY_SLOT_SIZE = 0xEC
    local PC_BOXES_SAVE_OFFSET = 0xC104

    print_debug("PC RAM scan: locating the live SaveData body and PCBoxes...")

    -- Gen IV BoxPokemon records are encrypted in the live/save representation.
    -- pokemon.read_data(address) performs the Gen IV PID-based decryption and
    -- checksum validation. The previous diagnostic incorrectly used is_raw=true,
    -- which treated the encrypted BoxPokemon as already decrypted.
    local function valid_boxmon(address)
        local pid = mdword(address)
        if pid == 0 then
            return false, nil, "pid=0"
        end

        -- For PC capacity/free-slot detection, a non-zero PID means the slot is
        -- occupied. Decoding can fail for an otherwise real boxed Pokemon, so
        -- pokemon.read_data() must never turn a non-zero-PID slot into a free slot.
        local data = pokemon.read_data(address)
        local species = nil
        local decode_reason = nil
        if data then
            local decoded_species = data[9] + bit.lshift(data[10], 8)
            if decoded_species >= 1 and decoded_species <= 493 then
                species = decoded_species
            else
                decode_reason = string.format("invalid species=%d", decoded_species)
            end
        else
            decode_reason = "pokemon.read_data failed"
        end

        return true, { pid = pid, species = species, decode_reason = decode_reason }, nil
    end

    -- Strict validator used ONLY while locating/alignment-validating PCBoxes.
    -- Unlike the occupancy check above, a candidate record must successfully
    -- decrypt and contain a valid Gen IV species. This prevents arbitrary
    -- non-zero RAM from being accepted as a boxed Pokemon alignment.
    local function strict_valid_boxmon(address)
        local pid = mdword(address)
        local checksum = mword(address + 0x06)
        if pid == 0 or checksum == 0 then
            return false
        end

        local data = pokemon.read_data(address)
        if not data then
            return false
        end

        local species = data[9] + bit.lshift(data[10], 8)
        return species >= 1 and species <= 493
    end

    local function read_pc_summary(base)
        if base < RAM_START or base + 0x121C7 >= RAM_END then
            return nil
        end

        local current_box = mdword(base)
        if current_box > 17 then
            return nil
        end

        local populated = 0
        local shown = 0
        local records = {}
        local box_populated = {}
        local box_free = {}

        for box = 0, 17 do
            box_populated[box + 1] = 0
        end

        for slot = 0, TOTAL_SLOTS - 1 do
            local mon_addr = base + 4 + slot * SLOT_SIZE
            local ok, info, invalid_reason = valid_boxmon(mon_addr)
            if ok then
                populated = populated + 1
                local box = math.floor(slot / 30) + 1
                box_populated[box] = box_populated[box] + 1
                if shown < 20 then
                    local pos = (slot % 30) + 1
                    if info.species then
                        records[#records + 1] = string.format(
                            "PC RAM: Box %d slot %d addr=0x%08X PID=%08X species=%d",
                            box, pos, mon_addr, info.pid, info.species)
                    else
                        records[#records + 1] = string.format(
                            "PC RAM: Box %d slot %d addr=0x%08X PID=%08X species=unknown (%s)",
                            box, pos, mon_addr, info.pid, info.decode_reason or "decode unavailable")
                    end
                    shown = shown + 1
                end
            else
                -- Diagnostic only: report every slot the scanner currently
                -- considers empty/invalid. This lets us identify false free
                -- slots in otherwise-full boxes without changing selection.
                local box = math.floor(slot / 30) + 1
                local pos = (slot % 30) + 1
                local raw_pid = mdword(mon_addr)
                local raw_checksum = mword(mon_addr + 0x06)
                print_debug(string.format(
                    "PC RAM DIAG: Box %d slot %d considered EMPTY/INVALID addr=0x%08X PID=%08X checksum=%04X reason=%s",
                    box, pos, mon_addr, raw_pid, raw_checksum, invalid_reason or "unknown"))
            end
        end

        for box = 1, 18 do
            box_free[box] = 30 - box_populated[box]
            print_debug(string.format("PC RAM: Box %d populated=%d free=%d", box, box_populated[box], box_free[box]))
        end

        pointers.pc_box_populated = box_populated
        pointers.pc_box_free = box_free

        return {
            current_box = current_box,
            populated = populated,
            records = records,
            box_populated = box_populated,
            box_free = box_free,
        }
    end

    -- Fast bounded search. Do NOT treat every 4-byte-aligned address as a
    -- possible PCBoxes base. That can accept a base shifted by exactly one
    -- 0x88-byte BoxPokemon slot: all of the real Pokemon still line up, but
    -- Box 1/Box 2 occupancy is shifted by one slot (the Step 19 false-positive
    -- at 0x0228B018 was exactly 0x88 before the real first record alignment).
    --
    -- Instead, find a real encrypted BoxPokemon record inside the small window
    -- first, then reconstruct candidate PCBoxes bases from the record stride.
    -- Score the candidates by how many neighbouring records validate on that
    -- same 0x88 alignment, and only run the full 540-slot summary on the best
    -- candidate. This mirrors the reliable alignment logic used by the full
    -- RAM fallback without scanning all 4 MB.
    -- Keep the bounded search ROM-specific. Platinum and Pearl place the live
    -- PCBoxes structure in different parts of RAM, so never reuse one game's
    -- fast window for the other. Games without a confirmed window fall back
    -- to the original full RAM scan below.
    local FAST_START = nil
    local FAST_END = nil
    local FAST_GAME = nil
    if _ROM.version == "PL" then
        FAST_START = 0x0228B000
        FAST_END = 0x0228B200
        FAST_GAME = "Platinum"
    elseif _ROM.version == "P" then
        FAST_START = 0x02279500
        FAST_END = 0x02279800
        FAST_GAME = "Pearl"
    elseif _ROM.version == "D" then
        FAST_START = 0x02279500
        FAST_END = 0x02279880
        FAST_GAME = "Diamond"
    end

    if FAST_START then
        print_debug(string.format(
            "PC RAM fast scan (%s): searching small window 0x%08X-0x%08X with BoxPokemon alignment validation...",
            FAST_GAME, FAST_START, FAST_END))

    local fast_best_base = nil
    local fast_best_hits = -1
    local fast_best_first_slot = 999

    -- The window is only used to find one or more genuine records. A candidate
    -- base may sit slightly before the window, so validate against main RAM.
    for address = FAST_START, FAST_END, 4 do
        local ok = strict_valid_boxmon(address)
        if ok then
            -- In practice the bounded window covers the start of Box 1. Try
            -- every Box-1 slot alignment for this genuine record. This avoids
            -- accepting an arbitrary currentBox-looking dword one record early.
            for candidate_slot = 0, 29 do
                local base = address - 4 - candidate_slot * SLOT_SIZE
                if base >= RAM_START and base + 4 + (TOTAL_SLOTS - 1) * SLOT_SIZE < RAM_END then
                    local current_box = mdword(base)
                    if current_box <= 17 then
                        local hits = 0
                        -- Score the first 30 slots. Real Box 1 records must all
                        -- remain on the same 0x88-byte alignment from this base.
                        for slot = 0, 29 do
                            local slot_ok = strict_valid_boxmon(base + 4 + slot * SLOT_SIZE)
                            if slot_ok then
                                hits = hits + 1
                            end
                        end

                        -- Prefer more correctly aligned Box-1 records. On a tie,
                        -- prefer the candidate that places the anchor record in
                        -- the earliest slot; this selects the natural start of
                        -- the structure instead of a one-record-early shift.
                        if hits > fast_best_hits or
                           (hits == fast_best_hits and candidate_slot < fast_best_first_slot) then
                            fast_best_hits = hits
                            fast_best_base = base
                            fast_best_first_slot = candidate_slot
                        end
                    end
                end
            end
        end
    end

    if fast_best_base and fast_best_hits >= 1 then
        local fast_summary = read_pc_summary(fast_best_base)
        if fast_summary and fast_summary.populated >= 1 then
            pointers.pc_boxes = fast_best_base
            pointers.pc_boxes_data = fast_best_base + 4
            print_debug(string.format(
                "PC RAM fast scan: FOUND aligned PCBoxes=0x%08X currentBox=%d populated=%d box1Valid=%d; full RAM search skipped",
                fast_best_base, fast_summary.current_box + 1,
                fast_summary.populated, fast_best_hits))
            for _, line in ipairs(fast_summary.records) do
                print_debug(line)
            end
            if fast_summary.populated > 20 then
                print_debug("PC RAM: first 20 populated slots shown; all 540 slots were checked")
            end
            return fast_best_base
        end
    end

        print_warn(string.format(
            "PC RAM fast scan (%s): small-window search did not validate; falling back to original RAM scan.",
            FAST_GAME))
    else
        print_debug("PC RAM fast scan: no ROM-specific small window configured; using original RAM scan.")
    end

    -- First method: use the party PID as an anchor to locate SaveData.body.
    -- Platinum's SaveData body contains the party at save offset 0xA0, with
    -- 0xEC-byte party Pokemon records. The PCBoxes page begins at 0xC104.
    local party_pids = {}
    local party_size = mbyte(pointers.party_count)
    if party_size > 6 then
        party_size = 6
    end

    for i = 1, party_size do
        if party[i] and party[i].pid then
            party_pids[i] = party[i].pid
        end
    end

    if next(party_pids) ~= nil then
        print_debug("PC RAM scan: using live party PID(s) to locate SaveData...")

        for address = RAM_START, RAM_END - PARTY_SAVE_OFFSET - (6 * PARTY_SLOT_SIZE), 4 do
            local first_pid = mdword(address)
            if first_pid ~= 0 then
                for party_slot = 1, party_size do
                    local expected_pid = party_pids[party_slot]
                    if expected_pid and first_pid == expected_pid then
                        local body_base = address - PARTY_SAVE_OFFSET - (party_slot - 1) * PARTY_SLOT_SIZE
                        if body_base >= RAM_START then
                            local saved_party_size = mbyte(body_base + 0x9C)
                            if saved_party_size >= party_size and saved_party_size <= 6 then
                                local all_match = true
                                for i = 1, party_size do
                                    local save_pid = mdword(body_base + PARTY_SAVE_OFFSET + (i - 1) * PARTY_SLOT_SIZE)
                                    if save_pid ~= party_pids[i] then
                                        all_match = false
                                        break
                                    end
                                end

                                if all_match then
                                    local pc_base = body_base + PC_BOXES_SAVE_OFFSET
                                    local summary = read_pc_summary(pc_base)
                                    if summary and summary.populated >= 1 then
                                        pointers.pc_boxes = pc_base
                                        pointers.pc_boxes_data = pc_base + 4
                                        pointers.save_data_body = body_base

                                        print_debug(string.format(
                                            "PC RAM scan: FOUND SaveData body=0x%08X PCBoxes=0x%08X currentBox=%d populated=%d",
                                            body_base, pc_base, summary.current_box + 1, summary.populated))
                                        for _, line in ipairs(summary.records) do
                                            print_debug(line)
                                        end
                                        if summary.populated > 20 then
                                            print_debug("PC RAM: first 20 populated slots shown; all 540 slots were checked")
                                        end
                                        return pc_base
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback: directly search main RAM for encrypted BoxPokemon records and
    -- reconstruct a PCBoxes base from their known 0x88-byte stride.
    print_debug("PC RAM scan: party anchor did not locate SaveData; trying direct BoxPokemon scan...")

    local best_base = nil
    local best_hits = 0

    for address = RAM_START, RAM_END - 0x100, 4 do
        local pid = mdword(address)
        local checksum = mword(address + 0x06)

        if pid ~= 0 and checksum ~= 0 then
            local ok = strict_valid_boxmon(address)
            if ok then
                for candidate_slot = 0, TOTAL_SLOTS - 1 do
                    local base = address - 4 - candidate_slot * SLOT_SIZE
                    if base >= RAM_START and base + 4 + (TOTAL_SLOTS - 1) * SLOT_SIZE < RAM_END then
                        local current_box = mdword(base)
                        if current_box <= 17 then
                            local nearby_hits = 0
                            local start_slot = math.max(0, candidate_slot - 4)
                            local end_slot = math.min(TOTAL_SLOTS - 1, candidate_slot + 4)
                            for slot = start_slot, end_slot do
                                local slot_ok = strict_valid_boxmon(base + 4 + slot * SLOT_SIZE)
                                if slot_ok then
                                    nearby_hits = nearby_hits + 1
                                end
                            end

                            if nearby_hits > best_hits then
                                best_hits = nearby_hits
                                best_base = base
                            end

                            if nearby_hits >= 2 then
                                local summary = read_pc_summary(base)
                                if summary and summary.populated >= 2 then
                                    pointers.pc_boxes = base
                                    pointers.pc_boxes_data = base + 4
                                    print_debug(string.format(
                                        "PC RAM scan: FOUND direct PCBoxes=0x%08X currentBox=%d populated=%d nearbyValid=%d",
                                        base, summary.current_box + 1, summary.populated, nearby_hits))
                                    for _, line in ipairs(summary.records) do
                                        print_debug(line)
                                    end
                                    if summary.populated > 20 then
                                        print_debug("PC RAM: first 20 populated slots shown; all 540 slots were checked")
                                    end
                                    return base
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if best_base then
        print_warn(string.format(
            "PC RAM scan: possible BoxPokemon cluster at 0x%08X, but it did not validate as PCBoxes (nearbyValid=%d)",
            best_base, best_hits))
    end

    print_warn("PC RAM scan: no validated PCBoxes structure found in main RAM.")
    return nil
end

--- Debug function for printing the memory address of a pointer
function print_pointer(pointer)
    local local_pointer = pointer - 0x2000000
    print(string.format("%06X", local_pointer))
end
