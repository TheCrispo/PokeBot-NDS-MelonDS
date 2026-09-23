-----------------------------------------------------------------------------
-- General bot methods for gen 4 games (DPPt, HGSS)
-- Author: wyanido, storyzealot
-- Homepage: https://github.com/wyanido/pokebot-nds
-----------------------------------------------------------------------------

function update_pointers()
    local anchor = mdword(0x21C489C + _ROM.offset)
    local foe_anchor = mdword(anchor + 0x226FE)
    local bag_page_anchor = mdword(anchor + 0x560EE)
    local roamer_anchor = mdword(anchor + 0x4272A)

    pointers = {
        start_value = 0x21066D4, -- 0 until save has been loaded
        -- items_pocket      = anchor + 0x59E,
        -- key_items_pocket  = anchor + 0x832,
        -- tms_hms_pocket    = anchor + 0x8FA,
        -- medicine_pocket   = anchor + 0xABA,
        -- berries_pocket    = anchor + 0xB5A,
        poke_balls_pocket = anchor + 0xC5A,
        
        party_count = anchor + 0xE,
        party_data  = anchor + 0x12,

        foe_count   = foe_anchor - 0x2B74,
        current_foe = foe_anchor - 0x2B70,

        map_header  = anchor + 0x11B2,
        menu_option = 0x21CDF22 + _ROM.offset,
        trainer_x   = 0x21CEF70 + _ROM.offset,
        trainer_y   = 0x21CEF74 + _ROM.offset,
        trainer_z   = 0x21CEF78 + _ROM.offset,
        facing      = anchor + 0x247C6,

        bike_gear = anchor + 0x123E,
        bike      = anchor + 0x1242,

        daycare_egg = anchor + 0x156E,

        selected_starter = anchor + 0x427A6,
        starters_ready   = anchor + 0x4282A,
        
        battle_bag_page        = bag_page_anchor + 0x4E,
        battle_menu_state      = anchor + 0x455A6,
        battle_menu_state2     = anchor - 0xD3FC,
        battle_indicator       = 0x21A1B2A + _ROM.offset,
        fishing_bite_indicator = 0x21D5E16 + _ROM.offset,

        trainer_name = anchor - 0x22,
        trainer_id   = anchor - 0x12,

        save_indicator = 0x21C491F + _ROM.offset,
        
        roamer = roamer_anchor + 0x20,
    }
end

--- Waits a random duration after a reset to decrease the odds of hitting duplicate seeds
function randomise_reset()
    wait_frames(200) -- White screen on startup

    local delay = math.random(100, 500)

    print_debug("Delaying " .. delay .. " frames...")
    wait_frames(delay)

    while not game_state.in_game do
        press_sequence("Start", 20, "A", math.random(8, 28))
    end
end

--- Opens the menu and selects the specified option
-- @param menu Name of the menu to open
function open_menu(menu)
    local option = {
        Pokedex = 1,
        Pokemon = 2,
        Bag = 4,
        Trainer = 5,
        Save = 7,
        Options = 8,
        Exit = 10
    }

    press_sequence("X", 8)
    
    -- Scroll up or down based on which navigation is shorter (doesn't acknowledge that the menu wraps around)
    local direction = option[menu] > mbyte(pointers.menu_option) and "Down" or "Up"
    while mbyte(pointers.menu_option) ~= option[menu] do
        press_sequence(direction, 8)
    end

    press_sequence("A", 90)
end

--- Returns an array of all Poke Balls within the Poke Balls bag pocket
function get_usable_balls()
    local balls = {}
    local slot = 0

    for i = pointers.poke_balls_pocket, pointers.poke_balls_pocket + 0x3A, 4 do
        local count = mword(i + 2)

        if count > 0 then
            local id = mword(i)
            local item_name = _ITEM[id + 1]

            balls[string.lower(item_name)] = slot + 1
        end

        slot = slot + 1
    end

    return balls
end

--- Returns true if the rod state has changed from being cast
function fishing_status_changed()
    return mbyte(pointers.fishing_bite_indicator) ~= 0
end

--- Returns true if a Pokemon is on the hook
function fishing_has_bite()
    return mbyte(pointers.fishing_bite_indicator) == 1
end

--- Returns true only when the exact Pokémon PID is no longer present in the party.
-- This is used to distinguish a successful box transfer from a full-box
-- rejection without ever selecting or depositing another party member.
local function party_no_longer_contains_pid(pid, frames)
    local limit = frames or 180
    for _ = 1, limit do
        process_frame()
        local present = false
        for i = 1, 6 do
            if party[i] and party[i].pid == pid then
                present = true
                break
            end
        end
        if not present then
            return true
        end
    end
    return false
end

--- Navigates to the Pokémon Center and deposits newly hatched non-target Pokémon.
-- `pending_checksums` identifies only Pokémon hatched by this bot run, so an
-- existing level-1 lead Pokémon is never mistaken for a newly hatched dud.
function deposit_hatched_duds(pending_hatched)
    if not pending_hatched or next(pending_hatched) == nil then
        return true
    end

    clear_all_inputs()

    move_to({z=646})
    move_to({x=553})

    -- Enter Pokémon Center.
    hold_button("Up")
    wait_frames(60)
    release_button("Up")
    wait_frames(120)

    hold_button("B")
    move_to({z=8})
    move_to({x=4})
    move_to({z=4})
    clear_all_inputs()

    -- Open the PC menus exactly as before. Once the actual PC party
    -- selection interface is reached, STOP completely so the next inputs
    -- can be directed step-by-step without the bot doing anything else.
    wait_frames(30)
    press_button("A")
    wait_frames(150)
    press_button("A")
    wait_frames(150)
    press_button("A")
    wait_frames(180)
    process_frame()

    clear_all_inputs()
    print("PC interface reached. Running directed PC input sequence...")

    -- Directed sequence from the PC party-selection screen:
    -- wait 1s -> A -> wait 1s -> A -> wait 2s -> Right -> A
    -- -> wait 1s -> A -> wait 1s -> A, then stop completely.
    wait_frames(60)
    press_button("A")
    wait_frames(60)
    press_button("A")
    wait_frames(120)
    press_button("Right")
    press_button("A")
    wait_frames(60)
    press_button("A")
    wait_frames(60)
    press_button("A")

    -- We are now on the Box menu. Read the live Gen IV PC storage RAM and
    -- find the first box with at least one free slot, starting from Box 1.
    -- The current screen is known to be Box 1, so navigation is deliberately
    -- based on that screen position rather than the saved current-box value.
    wait_frames(30)

    local pc_base = scan_pc_boxes_ram()
    if not pc_base then
        abort("Could not locate the live PC storage RAM.")
    end

    local free_boxes = pointers.pc_box_free
    local target_box = nil

    for box = 1, 18 do
        if free_boxes and free_boxes[box] and free_boxes[box] > 0 then
            target_box = box
            break
        end
    end

    if not target_box then
        abort("All 18 PC boxes are full.")
    end

    print(string.format("PC storage: first available box is Box %d (%d free slot(s)).",
        target_box, free_boxes[target_box]))

    -- scan_pc_boxes_ram() returns only after the complete PC RAM scan has
    -- finished. The game was paused while the scan was running, so give
    -- melonDS a clean settling period before sending any box-navigation
    -- inputs.
    print("[melonDS Lua] PC storage: RAM scan finished; waiting 3 seconds before selecting the box.")
    wait_frames(180)

    -- The scan is always performed from Box 1.
    -- Box 1 = 0 Rights, Box 2 = 1 Right, ... Box 18 = 17 Rights.
    local right_count = target_box - 1
    print(string.format(
        "[melonDS Lua] PC storage: on Box 1; moving Right %d time(s) to select Box %d.",
        right_count, target_box
    ))

    for i = 1, right_count do
        press_button("Right")
        wait_frames(30)
    end

    -- Place the newly hatched Pokémon into the selected box.
    press_button("A")
    wait_frames(60)

    -- Confirm the deposit from the live party data before attempting to leave
    -- the PC. process_frame()/wait_frames() continuously refreshes `party`, so
    -- after a successful deposit the queued Pokémon PID must no longer be in
    -- the party. The normal debug output may briefly show a checksum failure
    -- while the game rewrites the party, followed by "Party updated".
    local deposit_confirmed = true
    for pending_pid, pending_info in pairs(pending_hatched) do
        local still_in_party = false
        for slot = 1, 6 do
            if party[slot] and party[slot].pid == pending_pid then
                still_in_party = true
                break
            end
        end

        if still_in_party then
            deposit_confirmed = false
            print_warn("PC deposit not confirmed: queued Pokémon is still in the party.")
        else
            print_debug("PC deposit confirmed from party update for slot " ..
                tostring(pending_info.slot) .. ".")
        end
    end

    if not deposit_confirmed then
        print_warn("PC deposit could not be confirmed; leaving the PC open for inspection.")
        return false
    end

    -- The deposit is confirmed. Remove the completed queue entries so the
    -- hatching loop does not try to deposit the same Pokémon again.
    for pending_pid, _ in pairs(pending_hatched) do
        pending_hatched[pending_pid] = nil
    end

    -- Directed PC exit sequence:
    -- wait 1s -> B -> wait 1s -> B -> wait 5s -> B -> wait 4s -> B
    -- -> wait 2s. At that point we should be fully out of the PC and the
    -- existing caller resumes the egg-hatching route.
    wait_frames(60)
    press_button("B")
    wait_frames(60)
    press_button("B")
    wait_frames(300)
    press_button("B")
    wait_frames(240)
    press_button("B")
    wait_frames(120)

    -- Walk out of the Pokémon Center before the caller resumes the existing
    -- egg-hatching cycle. Because a single tap after a direction change can
    -- only turn the character, send one extra tap for each direction segment:
    -- Down x4, Right x6, Down x6. Every individual input is separated by a
    -- full 0.5-second (30-frame) gap, then wait 5 seconds before resuming.
    clear_all_inputs()
    print("PC exit complete; walking outside before resuming egg-hatching cycle.")

    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)

    press_button("Right")
    wait_frames(30)
    press_button("Right")
    wait_frames(30)
    press_button("Right")
    wait_frames(30)
    press_button("Right")
    wait_frames(30)
    press_button("Right")
    wait_frames(30)
    press_button("Right")
    wait_frames(30)

    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(30)
    press_button("Down")
    wait_frames(300)

    clear_all_inputs()
    print("Pokémon Center exit walk completed; resuming egg-hatching cycle.")
    return true
end

--- Returns the current stage of a Gen IV battle as a simple string.
-- DPPt and HGSS expose the same menu-state values through their game-specific pointers.
-- Step 28 diagnostic: log the raw DPPt battle-state bytes whenever either value changes.
local _last_battle_menu_state = nil
local _last_battle_menu_state2 = nil

function get_battle_state()
    if not game_state.in_battle then
        _last_battle_menu_state = nil
        _last_battle_menu_state2 = nil
        return nil
    end

    local state = mbyte(pointers.battle_menu_state)
    local state2 = mbyte(pointers.battle_menu_state2)

    if state ~= _last_battle_menu_state or state2 ~= _last_battle_menu_state2 then
        print_debug(string.format("Battle state debug: battle_menu_state=0x%02X battle_menu_state2=0x%02X", state, state2))
        _last_battle_menu_state = state
        _last_battle_menu_state2 = state2
    end

    if state2 == 0x2F then
        return "New Move"
    end

    if state == 0x1 then
        return "Menu"
    elseif state == 0x4 then
        return "Fight"
    elseif state == 0x8 then
        return "Bag"
    elseif state == 0xA then
        return "Pokemon"
    elseif state == 0x0E and state2 == 0x30 then
        -- Platinum forced party-selection screen after the active Pokemon faints.
        -- Confirmed from live Step 28 diagnostics.
        return "Pokemon"
    end

    return nil
end

--- Picks the specified starter Pokemon each reset until it's a target
function mode_starters()
    cycle_starter_choice()
    
    -- Diamond and Pearl need to skip through a cutscene before the briefcase
    local platinum = _ROM.version == "PL"

    if not platinum then 
        hold_button("Up")

        while game_state.map_name ~= "Lake Verity" do
            progress_text()
        end
        
        release_button("Up")
    end
    
    print("Waiting to open briefcase...")
    
    -- Skip until the starter can be selected, which
    -- is known when the lower 4 bits of the byte at
    -- the starters pointer equals the ready value
    local ready_value = platinum and 0xD or 0x5

    while bit.band(bit.band(mbyte(pointers.starters_ready), 15), ready_value) ~= ready_value do
        progress_text()
    end

    print("Selecting starter...")

    while mbyte(pointers.selected_starter) < starter do
        press_sequence("Right", 5)
    end

    -- Wait until starter is added to party
    while #party == 0 do
        progress_text()
    end

    -- Log encounter, stopping if necessary
    local mon = party[1]
    local is_target = pokemon.log_encounter(mon)

    if is_target then
        abort(mon.name .. " is a target!")
    else
        print(mon.name .. " was not a target, resetting...")
        soft_reset()
    end
end

--- Continuously moves back and forth until a wild battle starts.
-- Uses the existing shared wild-encounter handler for logging, target detection,
-- fleeing, battling non-targets, and auto-catching.
function mode_random_encounters()
    local function move_in_direction(dir)
        if emu.framecount() % 10 == 0 then -- Re-apply repel when configured/available through existing input behaviour
            press_button_async("A")
        end

        hold_button(dir)
        wait_frames(7)
        release_button(dir)
    end

    while true do
        check_party_status()

        print("Attempting to start a battle...")

        local dir1 = config.move_direction == "horizontal" and "Left" or "Up"
        local dir2 = config.move_direction == "horizontal" and "Right" or "Down"

        wait_frames(60) -- Wait to regain control post-battle
        hold_button("B")

        while not game_state.in_battle do
            move_in_direction(dir1)
            move_in_direction(dir2)
        end

        release_button("B")
        release_button(dir1)
        release_button(dir2)

        process_wild_encounter()
    end
end

--- Random encounter mode for very small patches of encounter terrain.
-- Returns to the position where the mode started before pacing locally.
function mode_random_encounters_small()
    print("WARNING: Do not use this mode with a bike")

    local home = {
        x = game_state.trainer_x,
        z = game_state.trainer_z
    }

    while true do
        check_party_status()

        print("Attempting to start a battle...")

        local dir1 = config.move_direction == "horizontal" and "Left" or "Up"
        local dir2 = config.move_direction == "horizontal" and "Right" or "Down"

        wait_frames(60) -- Wait to regain control post-battle
        hold_button("B")
        move_to_fixed(home)

        while not game_state.in_battle do
            press_sequence(dir1, 10, dir2, 10)
        end

        release_button("B")
        release_button(dir1)
        release_button(dir2)

        process_wild_encounter()
    end
end

function mode_daycare_eggs()
    local SEGMENT_TILES = 32
    local STUCK_FRAMES = 180
    local pending_hatched_duds = {}

    local function mount_bike()
        -- Keep the existing working bike behaviour unchanged.
        if mbyte(pointers.bike) ~= 1 then
            press_sequence("Y", 5)
        end
        if mbyte(pointers.bike_gear) ~= 1 then
            press_button("B")
        end
    end

    local function return_to_hatching_route()
        clear_all_inputs()

        -- The Day-Care Man is not on the hatching lane.
        -- After collecting an egg we must explicitly reacquire BOTH
        -- coordinates of the known straight hatching path.
        -- Otherwise the bot would only move to the hatching-lane X while
        -- remaining at the Day-Care Man's Z coordinate, then start moving
        -- Down/Up from the wrong place.
        print_debug(string.format("Reacquiring hatching lane from X=%s Z=%s",
            tostring(game_state.trainer_x), tostring(game_state.trainer_z)))

        -- The correct hatching lane is X=562. X=561 was one tile too far
        -- left when returning from the Day Care building.
        move_to({x=562}, check_hatching_eggs)
        move_to({z=662}, check_hatching_eggs)

        -- Step 46: do not treat merely crossing the target coordinate as a
        -- completed reacquire. Release movement, allow the overworld position
        -- to settle, then verify it again before the hatch cycle resumes.
        clear_all_inputs()
        wait_frames(15)

        local settle_attempts = 0
        while settle_attempts < 3 and
              (math.abs(game_state.trainer_x - 562.5) > 0.5 or
               math.abs(game_state.trainer_z - 662.0) > 0.5) do
            print_debug(string.format("Hatching lane settle check moved to X=%s Z=%s; reacquiring",
                tostring(game_state.trainer_x), tostring(game_state.trainer_z)))
            move_to({x=562}, check_hatching_eggs)
            move_to({z=662}, check_hatching_eggs)
            clear_all_inputs()
            wait_frames(15)
            settle_attempts = settle_attempts + 1
        end

        print_debug(string.format("Hatching lane reacquired and settled at X=%s Z=%s",
            tostring(game_state.trainer_x), tostring(game_state.trainer_z)))
    end

    -- D/P/Pt will still report a Day-Care Egg while we are carrying an Egg
    -- in the party. Do not keep checking the Day-Care Man during the final
    -- part of the hatch cycle, otherwise the route can leave the hatching
    -- lane and interrupt the pending "Oh?" hatch prompt.
    --
    -- The Gen IV Egg cycle counter is stored in the same byte as friendship
    -- (party BoxPokemon offset 0x14). In D/P/Pt one Egg cycle is 255 steps.
    -- Once the remaining Egg cycles are down to 2 or less, there are at most
    -- about 510 steps left, so suspend all Day-Care checks. The check is
    -- automatically re-enabled after the Egg -> Pokemon transition.
    local DAYCARE_CHECK_MIN_EGG_STEPS = 512

    local function should_check_daycare()
        local lowest_egg_steps = nil

        -- Slot 1 is protected and is never used for the hatching/deposit
        -- workflow. Eggs relevant to this routine are slots 2-6.
        for i = 2, 6 do
            local mon = party[i]
            if mon and mon.isEgg == true then
                local cycles = tonumber(mon.friendship) or 0
                local egg_steps = cycles * 255

                if lowest_egg_steps == nil or egg_steps < lowest_egg_steps then
                    lowest_egg_steps = egg_steps
                end
            end
        end

        if lowest_egg_steps ~= nil and lowest_egg_steps < DAYCARE_CHECK_MIN_EGG_STEPS then
            return false
        end

        return true
    end

    local function collect_egg_if_available()
        if #party == 6 then
            return false
        end

        -- Platinum's daycare_egg pointer is non-zero when an Egg is available.
        -- If it is zero, leave immediately and continue hatching.
        if mdword(pointers.daycare_egg) == 0 then
            print_debug("No Egg available at the Day Care; returning to hatching.")
            return false
        end

        print("Egg available at the Day Care. Collecting...")

        -- Known-good route to the Day-Care Man outside the Solaceon Day Care.
        move_to({z=648}, check_hatching_eggs)
        move_to({x=556}, check_hatching_eggs)
        clear_all_inputs()

        local old_party_count = #party
        local timeout = 0
        while #party == old_party_count and timeout < 600 do
            progress_text()
            timeout = timeout + 1
        end

        if #party > old_party_count then
            print("Egg collected.")
            -- Synchronize the hatch detector immediately after collecting the
            -- new egg. This prevents an empty slot changing nil -> Egg from
            -- being mistaken for an Egg -> Pokémon hatch on the next frame.
            party_egg_states = get_party_egg_states()
            print_debug("Hatch detector synchronized after Egg collection")
        else
            print_warn("Day-Care interaction did not add an Egg; returning to hatching.")
        end

        return_to_hatching_route()
        return #party > old_party_count
    end

    process_frame()
    party_egg_states = get_party_egg_states()
    mount_bike()
    return_to_hatching_route()

    local direction = "Up"
    local segment_distance = 0
    local stuck_frames = 0
    local last_x = game_state.trainer_x
    local last_z = game_state.trainer_z
    local total_tiles = 0

    print("Starting DPPt automatic egg-hatching cycle...")

    while true do
        -- Deposit only Pokémon that were actually hatched by this run.
        if next(pending_hatched_duds) ~= nil then
            clear_all_inputs()
            print("Newly hatched non-target detected; heading to the PC to deposit it...")
            local deposit_ok = deposit_hatched_duds(pending_hatched_duds)
            if deposit_ok == false then
                abort("PC deposit failed; PC left open for inspection.")
            end
            process_frame()
            party_egg_states = get_party_egg_states()
            mount_bike()
            return_to_hatching_route()
            -- Step 46: returning from the PC is a fresh hatch-route start.
            -- Always begin from the fixed tile by travelling Up first; do not
            -- inherit a pre-deposit Down segment, which can shift the cycle
            -- below the intended lane.
            direction = "Up"
            last_x = game_state.trainer_x
            last_z = game_state.trainer_z
            stuck_frames = 0
            segment_distance = 0
        elseif not game_state.in_game then
            clear_all_inputs()
            progress_text()
            last_x = game_state.trainer_x
            last_z = game_state.trainer_z
            stuck_frames = 0
        elseif game_state.in_battle then
            clear_all_inputs()
            flee_battle()
            last_x = game_state.trainer_x
            last_z = game_state.trainer_z
            stuck_frames = 0
        else
            -- Only queue the exact party slot returned by
            -- check_hatching_eggs(stuck_frames). Do NOT scan the party here. During the
            -- hatch animation the party data can already report the new
            -- Pokémon as non-egg, which made the previous implementation
            -- incorrectly treat every existing non-egg as newly hatched.
            hold_button(direction)
            local hatch_processed, hatched_slot = check_hatching_eggs(stuck_frames)

            -- An egg hatch temporarily stops overworld movement while the
            -- hatch animation runs. During that time trainer_x/trainer_z do
            -- not change, so the normal movement watchdog would otherwise
            -- start reversing Up/Down. A hatch is triggered from the existing
            -- stopped-movement state; Egg -> Pokemon is only confirmation.
            local x = game_state.trainer_x
            local z = game_state.trainer_z
            local moved = (x ~= last_x) or (z ~= last_z)

            if hatch_processed then
                -- hatched_slot is the slot whose Egg -> Pokémon transition was
                -- actually detected. Slot 1 is deliberately protected: it is
                -- the user's lead Pokémon and must never be deposited.
                if hatched_slot and hatched_slot >= 2 and hatched_slot <= 6 then
                    local hatched = party[hatched_slot]
                    if hatched and not hatched.isEgg then
                        if not pokemon.matches_ruleset(hatched, config.target_traits) then
                            pending_hatched_duds[hatched.pid] = {
                                slot = hatched_slot,
                                pid = hatched.pid,
                                checksum = hatched.checksum,
                                name = hatched.name
                            }
                            print_debug("Exact hatch queued for PC: " .. hatched.name ..
                                " slot=" .. hatched_slot .. " pid=" .. tostring(hatched.pid))
                        else
                            print_debug("Hatched target in slot " .. hatched_slot .. ": " .. hatched.name)
                        end
                    else
                        print_warn("Hatch transition was detected in slot " .. tostring(hatched_slot) ..
                            " but the slot is not currently a Pokémon.")
                    end
                elseif hatched_slot == 1 then
                    print_debug("Hatch detected in protected party slot 1; never depositing slot 1.")
                else
                    print_warn("Hatch animation completed but no valid party slot was returned.")
                end

                clear_all_inputs()
                segment_distance = 0
                stuck_frames = 0
                last_x = x
                last_z = z
                print_debug("Egg hatched; resetting movement watchdog instead of reversing direction")
            else
                if moved then
                    local delta = math.abs(x - last_x) + math.abs(z - last_z)
                    segment_distance = segment_distance + delta
                    total_tiles = total_tiles + delta
                    stuck_frames = 0
                else
                    -- While an Egg is present, the hatch detector uses this
                    -- real stopped-movement count to decide when to press A.
                    -- Keep counting rather than suppressing the stall signal.
                    local current_egg_states = get_party_egg_states()
                    local egg_present = false
                    for i = 1, 6 do
                        if current_egg_states[i] == true then
                            egg_present = true
                            break
                        end
                    end

                    stuck_frames = stuck_frames + 1
                end

                last_x = x
                last_z = z

                if segment_distance >= SEGMENT_TILES then
                    direction = (direction == "Up") and "Down" or "Up"
                    segment_distance = 0
                    stuck_frames = 0
                    print_debug("Egg hatching: reversing direction after " .. total_tiles .. " total tiles")
                elseif stuck_frames >= STUCK_FRAMES then
                    direction = (direction == "Up") and "Down" or "Up"
                    segment_distance = 0
                    stuck_frames = 0
                    print_warn("Egg hatching: no movement detected; reversing direction")
                end
            end

            -- If there is room in the party, check the Day Care. While an
            -- Egg has fewer than 512 estimated steps remaining, DO NOT go to
            -- the Day-Care Man. Wait for the current Egg to hatch first. This
            -- prevents the route from interrupting the final hatch cycle and
            -- getting stuck on the "Oh?" message. After the Egg -> Pokemon
            -- transition, should_check_daycare() becomes true again.
            if #party < 6 and should_check_daycare() then
                clear_all_inputs()
                collect_egg_if_available()
                mount_bike()
            end
        end
    end
end

function mode_roamers()
    local data
    local a_cooldown = 0
    local is_unencrypted = _ROM.version ~= "PL" -- Only Platinum encrypts roamer data after generating it 

    if not config.ot_override then
        abort("You must set your TID/SID override before you can start.") -- Prevents mode from beginning if override is not set.
    end

    while not data do
        data = pokemon.read_data(pointers.roamer, is_unencrypted)

        if a_cooldown == 0 then
            press_button_async("A")
            a_cooldown = math.random(5, 20)
        else
            a_cooldown = a_cooldown - 1
        end

        wait_frames(1)
    end

    local mon = pokemon.parse_data(data, true)

    if config.ot_override then
        mon.otSID = tonumber(config.sid_override) -- SID is not generated during initial encounter. This will prevent false flagging.
        mon.otID = tonumber(config.sid_override) -- Sets the ID as well for those who are overriding it from their usual TID.
    end

    local is_target = pokemon.log_encounter(mon)
    
    if mon.name == "Unown" then
        abort("Please clear the journal and then save to resume.") -- The journal is read as 'Unown'. This will stop pointless resets.
    end
    
    if is_target then
        abort(mon.name .. " is a target!")
    else
        soft_reset()
    end
end

--- Proceeds through the D/P/Pt egg hatch sequence.
-- The caller only enters this function after a LIVE party-memory read has
-- confirmed that the exact party slot changed from Egg -> non-Egg.
function hatch_egg(slot)
    press_sequence(30, "B", 30)

    -- Mon data changes again once animation finishes
    local checksum = party[slot].checksum
    while party[slot].checksum == checksum do
        press_sequence("B", 5)
    end
end

--- Converts bytes into readable text using the game's respective encoding method.
-- @param input Table of bytes or memory address to read from
-- @param pointer Offset into the byte table if provided
function read_string(input, pointer)
    local char_table = {
        "　", "ぁ", "あ", "ぃ", "い", "ぅ", "う", "ぇ", "え", "ぉ", "お", "か", "が", "き", "ぎ",
        "く", "ぐ", "け", "げ", "こ", "ご", "さ", "ざ", "し", "じ", "す", "ず", "せ", "ぜ", "そ", "ぞ",
        "た", "だ", "ち", "ぢ", "っ", "つ", "づ", "て", "で", "と", "ど", "な", "に", "ぬ", "ね", "の",
        "は", "ば", "ぱ", "ひ", "び", "ぴ", "ふ", "ぶ", "ぷ", "へ", "べ", "ぺ", "ほ", "ぼ", "ぽ", "ま",
        "み", "む", "め", "も", "ゃ", "や", "ゅ", "ゆ", "ょ", "よ", "ら", "り", "る", "れ", "ろ", "わ",
        "を", "ん", "ァ", "ア", "ィ", "イ", "ゥ", "ウ", "ェ", "エ", "ォ", "オ", "カ", "ガ", "キ", "ギ",
        "ク", "グ", "ケ", "ゲ", "コ", "ゴ", "サ", "ザ", "シ", "ジ", "ス", "ズ", "セ", "ゼ", "ソ", "ゾ",
        "タ", "ダ", "チ", "ヂ", "ッ", "ツ", "ヅ", "テ", "デ", "ト", "ド", "ナ", "ニ", "ヌ", "ネ", "ノ",
        "ハ", "バ", "パ", "ヒ", "ビ", "ピ", "フ", "ブ", "プ", "ヘ", "ベ", "ペ", "ホ", "ボ", "ポ", "マ",
        "ミ", "ム", "メ", "モ", "ャ", "ヤ", "ュ", "ユ", "ョ", "ヨ", "ラ", "リ", "ル", "レ", "ロ", "ワ",
        "ヲ", "ン", "０", "１", "２", "３", "４", "５", "６", "７", "８", "９", "Ａ", "Ｂ", "Ｃ", "Ｄ",
        "Ｅ", "Ｆ", "Ｇ", "Ｈ", "Ｉ", "Ｊ", "Ｋ", "Ｌ", "Ｍ", "Ｎ", "Ｏ", "Ｐ", "Ｑ", "Ｒ", "Ｓ", "Ｔ",
        "Ｕ", "Ｖ", "Ｗ", "Ｘ", "Ｙ", "Ｚ", "ａ", "ｂ", "ｃ", "ｄ", "ｅ", "ｆ", "ｇ", "ｈ", "ｉ", "ｊ",
        "ｋ", "ｌ", "ｍ", "ｎ", "ｏ", "ｐ", "ｑ", "ｒ", "ｓ", "ｔ", "ｕ", "ｖ", "ｗ", "ｘ", "ｙ", "ｚ",
        "",   "！", "？", "、", "。", "…", "・", "／", "「", "」", "『", "』", "（", "）", "♂", "♀",
        "＋", "ー", "×", "÷", "＝", "～", "：", "；", "．", "，", "♠", "♣", "♥", "♦", "★", "◎",
        "○", "□", "△", "◇", "＠", "♪", "％", "☀", "☁", "☂", "☃", "😑", "☺", "☹", "😠", "⤴︎",
        "⤵︎", "💤", "円", "💰", "🗝️", "💿", "✉️", "💊", "🍓", "◓", "💥", "←", "↑", "↓", "→", "►",
        "＆", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E",
        "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U",
        "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k",
        "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "À",
        "Á", "Â", "Ã", "Ä", "Å", "Æ", "Ç", "È", "É", "Ê", "Ë", "Ì", "Í", "Î", "Ï", "Ð",
        "Ñ", "Ò", "Ó", "Ô", "Õ", "Ö", "×", "Ø", "Ù", "Ú", "Û", "Ü", "Ý", "Þ", "ß", "à",
        "á", "â", "ã", "ä", "å", "æ", "ç", "è", "é", "ê", "ë", "ì", "í", "î", "ï", "ð",
        "ñ", "ò", "ó", "ô", "õ", "ö", "÷", "ø", "ù", "ú", "û", "ü", "ý", "þ", "ÿ", "Œ",
        "œ", "Ş", "ş", "ª", "º", "er", "re", "r", "₽", "¡", "¿", "!", "?", ",", ".", "…",
        "･", "/", "‘", "’", "“", "”", "„", "«", "»", "(", ")", "♂", "♀", "+", "-", "*",
        "#", "=", "&", "~", ":", ";", "♠", "♣", "♥", "♦", "★", "◎", "○", "□", "△", "◇",
        "@", "♪", "%", "☀", "☁", "☂", "☃", "😑", "☺", "☹", "😠", "⤴︎", "⤵︎", "💤", " ", "e",
        "PK", "MN", " ", " ", " ", "", " ", " ", "°", "_", "＿", "․", "‥",
    }
    local text = ""

    if type(input) == "table" then
        -- Read data from an inputted table of bytes
        for i = pointer + 1, #input, 2 do
            local value = input[i] + bit.lshift(input[i + 1], 8)

            if value == 0xFFFF or value == 0x0000 then -- Null terminator
                break
            end

            text = text .. (char_table[value] or "?")
        end
    else
        -- Read data from an inputted address
        for i = input, input + 32, 2 do
            local value = mword(i)

            if value == 0xFFFF or value == 0x0000 then -- Null terminator
                break
            end

            text = text .. (char_table[value] or "?")
        end
    end

    return text
end


