-----------------------------------------------------------------------------
-- General bot methods for all games
-- Author: wyanido, storyzealot
-- Homepage: https://github.com/wyanido/pokebot-nds
-----------------------------------------------------------------------------

--- Logs wild encounters without automated inputs while the user plays
function mode_manual()
    while true do
        while not game_state.in_battle do
            process_frame()
        end

        for i = 1, #foe, 1 do
            pokemon.log_encounter(foe[i])
        end

        while game_state.in_battle do
            process_frame()
        end
    end
end

--- Continuously reels in Pokemon with the registered fishing rod
function mode_fishing()
    while not game_state.in_battle do
        local before_cast = mbyte(pointers.fishing_bite_indicator)
        print(string.format("Fishing debug: before cast indicator=%d", before_cast))

        press_button("Y")
        wait_frames(60)

        local last_indicator = mbyte(pointers.fishing_bite_indicator)
        print(string.format("Fishing debug: after cast wait indicator=%d", last_indicator))

        while not fishing_status_changed() do
            wait_frames(1)
            local indicator = mbyte(pointers.fishing_bite_indicator)
            if indicator ~= last_indicator then
                print(string.format("Fishing debug: indicator changed %d -> %d", last_indicator, indicator))
                last_indicator = indicator
            end
        end

        local result_indicator = mbyte(pointers.fishing_bite_indicator)
        print(string.format("Fishing debug: status detected indicator=%d bite=%s", result_indicator, tostring(fishing_has_bite())))

        if fishing_has_bite() then
            print("Landed a Pokemon!")
            break
        else
            print("Not even a nibble...")
            press_sequence(30, "A", 20)
        end
    end

    while not game_state.in_battle do
        progress_text()
    end

    process_wild_encounter()

    wait_frames(90)
end

--- Returns the index of the first non-fainted Pokémon in the party
function get_lead_mon_index()
    for i = 1, 6, 1 do
        if party[i].currentHP ~= 0 then
            return i
        end 
    end
end

--- Finds and uses the best available options to safely weaken the foe
function subdue_pokemon()
    -- Ensure target has no recoil moves before attempting to weaken it
    local recoil_moves = {"Brave Bird", "Double-Edge", "Flare Blitz", "Head Charge", "Head Smash", "Self-Destruct",
                            "Take Down", "Volt Tackle", "Wild Charge", "Wood Hammer"}
    local recoil_slot = 0

    for _, v in ipairs(recoil_moves) do
        recoil_slot = pokemon.get_move_slot(foe[1], v)

        if recoil_slot ~= 0 then
            print_warn("The target has a recoil move. False Swipe won't be used.")
            break
        end
    end

    if recoil_slot == 0 then
        -- Check whether the lead actually has False Swipe
        local false_swipe_slot = pokemon.get_move_slot(party[get_lead_mon_index()], "False Swipe")

        if false_swipe_slot == 0 then
            print_warn("The lead Pokemon can't use False Swipe.")
        else
            use_move(false_swipe_slot)
        end
    end
    
    -- Status moves in order of usefulness
    local status_moves = {"Spore", "Sleep Powder", "Lovely Kiss", "Dark Void", "Hypnosis", "Sing", "Grass Whistle",
                            "Thunder Wave", "Glare", "Stun Spore"}
    local status_slot = 0

    for i = 1, #foe[1].type, 1 do
        if foe[1].type[i] == "Ground" then
            print_debug("Foe is Ground-type. Thunder Wave can't be used.")
            table.remove(status_moves, 8) -- Remove Thunder Wave from viable options if target is Ground type
            break
        end
    end

    -- Remove Grass type status moves if target has Sap Sipper
    if foe[1].ability == "Sap Sipper" then
        local grass_moves = {"Spore", "Sleep Powder", "Grass Whistle", "Stun Spore"}

        for i, k in ipairs(grass_moves) do
            for i2, k2 in pairs(status_moves) do
                if k == k2 then
                    table.remove(status_moves, i2)
                    break
                end
            end
        end
    end

    for _, v in ipairs(status_moves) do
        status_slot = pokemon.get_move_slot(party[get_lead_mon_index()], v)

        if status_slot ~= 0 then
            break
        end
    end

    if status_slot > 0 then
        -- Bot will blindly use the status move once and hope it lands
        use_move(status_slot)
    else
        print_warn("The lead Pokemon has no usable status moves.")
    end
end


-- Platinum: exact live Poké Ball pocket location.
-- pt.lua's `anchor` is the live Platinum small save block address + 0x14.
-- The documented Platinum Balls pocket is at save offset 0xCEC.
-- Therefore the live pocket is:
--     anchor + (0xCEC - 0x14) = anchor + 0xCD8
--
-- This is also consistent with pt.lua:
--   trainer name = anchor + 0x7C  (save 0x68 + 0x14)
--   trainer ID   = anchor + 0x8C  (save 0x78 + 0x14)
local function get_platinum_ball_pocket()
    if pointers.poke_balls_pocket then
        return pointers.poke_balls_pocket
    end

    local anchor = mdword(0x021C0794 + _ROM.offset)
    if anchor == 0 then
        return nil
    end

    return anchor + 0xCD8
end

--- Continuously tries to catch the foe until the battle ends, or there are no valid Poke Balls left
function catch_pokemon()
    local function get_preferred_ball(balls)
        -- Compare with override ruleset first
        if config.pokeball_override then
            for ball, _ in pairs(config.pokeball_override) do
                if pokemon.matches_ruleset(foe[1], config.pokeball_override[ball]) then
                    local index = balls[string.lower(ball)]

                    if index then
                        print_debug("Bot will use " .. ball .. " from slot " .. ((index - 1) % 6) .. ", page " .. math.floor(index / 6))
                        return index
                    end
                end
            end
        end

        -- If no override rules were matched, default to priority
        if config.pokeball_priority then
            for _, ball in ipairs(config.pokeball_priority) do
                local index = balls[string.lower(ball)]

                if index then
                    print_debug("Bot will use " .. ball .. " from slot " .. ((index - 1) % 6) .. ", page " .. math.floor(index / 6))
                    return index
                end
            end
        end

        return -1
    end

    local function use_ball(index)
        -- Platinum's battle-ball layout in this ROM exposes a single page.
        -- Do not use the generic left/right page taps: the lower-left control
        -- is BACK on this layout.
        local page = math.floor((index - 1) / 6)
        if page ~= 0 then
            abort("Selected Poke Ball is beyond the first Platinum battle-bag page")
        end

        local button = (index - 1) % 6 + 1
        local x = 80 * ((button - 1) % 2 + 1)
        local y = 30 + 50 * math.floor((button - 1) / 2)

        print_debug(string.format("Selecting Platinum visible ball slot %d at (%d,%d)", index, x, y))
        touch_screen_at(x, y)
        wait_frames(30)
        touch_screen_at(108, 176) -- USE
    end

    if config.subdue_target then 
        subdue_pokemon()
    end

    while game_state.in_battle do
        -- Platinum battle bag uses the live Bag.pokeballs array.
        -- Empty slots are compacted by the game, so the non-empty entries
        -- correspond directly to the visible battle-bag slots.
        local balls = {}
        local visible_slot = 1
        local ball_pocket = get_platinum_ball_pocket()

        if not ball_pocket then
            abort("Could not locate Platinum save data in RAM")
        end

        print_debug(string.format("Platinum Balls pocket: %08X", ball_pocket))

        for i = ball_pocket, ball_pocket + 0x38, 4 do
            local count = mword(i + 2)
            if count > 0 then
                local id = mword(i)
                local item_name = _ITEM[id + 1]
                if item_name then
                    balls[string.lower(item_name)] = visible_slot
                    print_debug("Platinum visible ball slot " .. visible_slot .. ": " .. item_name .. " x" .. count)
                    visible_slot = visible_slot + 1
                end
            end
        end

        local ball_index = get_preferred_ball(balls)
        
        if ball_index == -1 then
            abort("No valid Poke Balls to catch the target with")
        end

        while mbyte(pointers.battle_menu_state) ~= 1 do
            press_sequence("B", 8)
        end

        wait_frames(20)

        touch_screen_at(38, 174)
        wait_frames(90)

        touch_screen_at(192, 36)
        wait_frames(90)

        use_ball(ball_index)

        -- Wait until catch failed or battle ended
        while mbyte(pointers.battle_menu_state) ~= 1 and game_state.in_battle do
            press_sequence("B", 8)
            touch_screen_at(0, 0) -- Skip Pokedex entry screen in HGSS without pressing A to avoid accidental menu inputs 
        end
    end

    print("Skipping through all post-battle dialogue... (This may take a few seconds)")

    for i = 0, 59, 1 do
        press_sequence("B", 10)
    end

    if config.save_game_after_catch then
        save_game()
    end
end

--- Logs the current wild foes and decides the next actions to take
function process_wild_encounter()
    clear_all_inputs()
    wait_frames(30)

    -- Check all foes in case of a double battle
    local is_target = false
    local foe_item = false
    local foe_name = foe[1].name

    for i, mon in ipairs(foe) do
        is_target = pokemon.log_encounter(mon) or is_target

        if mon.heldItem ~= "none" then
            foe_item = true
        end
    end

    if is_target then
        print("Wild " .. foe_name .. " is a target!")

        if config.auto_catch then
            while game_state.in_battle do
                catch_pokemon()
            end
        else
            abort("Stopping script for manual catch")
        end
    else
        while game_state.in_battle and foe do
            if #foe == 2 then
                print("Won't battle two targets at once. Fleeing!")
                flee_battle()
            else
                -- Thief wild items (previously do_thief)
                local lead = get_lead_mon_index()
                local thief_slot = pokemon.get_move_slot(party[lead], "Thief")

                if config.thief_wild_items and foe_item and thief_slot ~= 0 then
                    print(foe_name .. " has a held item. Using Thief and fleeing...")

                    while get_battle_state() ~= "Menu" do
                        press_sequence("B", 5)
                    end

                    use_move(thief_slot)
                    flee_battle()
                elseif config.battle_non_targets then
                    print(foe_name .. " was not a target. Battling...")

                    while game_state.in_battle do
                        battle_foe()
                    end
                else
                    print(foe_name .. " was not a target. Fleeing!")
                    flee_battle()
                end
            end
        end
    end

    if config.pickup then
        do_pickup()
    end
end

--- Collects held items from Pickup Pokemon if enough have accumulated
function do_pickup()
    local item_count = 0

    for i, mon in ipairs(party) do
        if mon.ability == "Pickup" and mon.heldItem ~= "none" then
            item_count = item_count + 1
        end
    end

    if item_count >= tonumber(config.pickup_threshold) then
        open_menu("Pokemon")

        for _, mon in ipairs(party) do
            if mon.ability == "Pickup" and mon.heldItem ~= "none" then
                press_sequence("A", 8, "Up", 8, "Up", 8, "A", 22, "Down", 8, "A")
                wait_frames(90)
                press_button("B")
            end

            press_sequence("Right", 5)
        end
        
        press_sequence(30, "B", 120, "B", 60)
    else
        print_debug(item_count .. " Pickup items in party. Collecting at " .. config.pickup_threshold)
    end
end

--- Saves the game
function save_game()
    print("Saving game...")

    -- A movement mode may have been holding a direction immediately before the
    -- target encounter.  Start the save sequence from a completely neutral
    -- controller state so that input cannot leak into the menu/save dialogue.
    print_debug("Save: releasing all inputs before opening the menu.")
    clear_all_inputs()
    wait_frames(12)

    print_debug("Save: opening the Save menu option.")
    open_menu("Save")

    print_debug("Save: confirming the save prompts.")
    clear_all_inputs()
    press_sequence("A", 90, "A", 60)
    
    -- Some game-specific pointer tables (notably Platinum) do not expose
    -- save_indicator.  Do not try to read a nil address in that case.
    if pointers.save_indicator ~= nil then
        print_debug("Save: waiting for save_indicator to report completion.")
        while mbyte(pointers.save_indicator) ~= 0 do
            press_sequence("A", 12)
        end
    else
        print_debug("No save_indicator pointer for this game; using timed save completion fallback.")
        print_debug("Save: waiting through Platinum save completion window.")
        for i = 1, 50 do
            press_sequence("A", 12)
        end
    end

    if _EMU == "BizHawk" then
        client.saveram() -- Flush save ram to the disk	
    end

    print_debug("Save: closing any remaining save dialogue.")
    clear_all_inputs()
    press_sequence("B", 10)

    -- Do not return to the active mode with a stale held direction/button.
    clear_all_inputs()
    wait_frames(12)
    print_debug("Save: sequence finished with all inputs released.")
end

-- Selects a move on the FIGHT menu
-- @param id The move index in the moveset
function use_move(id)
    wait_frames(30)
    touch_screen_at(128, 90)
    wait_frames(30)

    local x = 80 * ((id - 1) % 2 + 1)
    local y = 50 * (math.floor((id - 1) / 2) + 1)
    touch_screen_at(x, y)
    wait_frames(60)
end

--- Attemps to KO the current foe
function battle_foe()
    local waiting_for_manual_replacement = false

    while get_battle_state() ~= "Menu" do
        local battle_state = get_battle_state()

        -- Do not automatically switch Pokemon during battle. If Platinum opens
        -- the forced party screen after a faint, leave the controls untouched
        -- and wait for the player to choose the replacement manually.
        if battle_state == "Pokemon" then
            if not waiting_for_manual_replacement then
                print_warn("Active Pokemon fainted. Waiting for manual replacement...")
                clear_all_inputs()
                waiting_for_manual_replacement = true
            end
            wait_frames(1)
        else
            waiting_for_manual_replacement = false
            press_sequence("B", 5) -- Also cancels evolutions
        end

        if not game_state.in_battle then -- Battle finished, back in the overworld
            return
        elseif get_battle_state() == "New Move" then -- These cases are annoying and require specific inputs to cancel
            wait_frames(30)
            touch_screen_at(125, 115)
            wait_frames(100)
            press_button("B")
            wait_frames(100)
            touch_screen_at(125, 65)
            wait_frames(60)
            press_button("B")
            wait_frames(120)
            return
        end
    end
    
    -- Refresh the party immediately before choosing an attack so current PP is used.
    -- PP is stored in the party Pokemon data and can change after every move.
    update_party()

    local lead = get_lead_mon_index()
    local best_move = pokemon.find_best_attacking_move(party[lead], foe[1])
    
    if best_move.power > 0 then
        local current_pp = party[lead].pp[best_move.index] or 0
        print_debug("Best move is " .. best_move.name .. " (Avg Power: " .. best_move.power ..
            ", PP: " .. current_pp .. ")")
        use_move(best_move.index)
    else
        print("Lead Pokemon has no valid moves left to battle! Fleeing...")
        flee_battle()
    end
end

--- Manages the party between battles to make sure the bot can proceed with its task
function check_party_status()
    local function is_healthy(mon)
        local pp = 0

        for i, move in ipairs(mon.moves) do
            if move.power ~= nil then
                pp = pp + mon.pp[i]
            end
        end

        return mon.currentHP > mon.maxHP / 5 and pp > 3 and not mon.isEgg
    end

    if #party == 0 or game_state.in_battle then -- Don't check party status if bot was started during a battle
        return nil
    end

    if not is_healthy(party[get_lead_mon_index()]) then
        if not config.cycle_lead_pokemon then
            abort("Lead Pokemon is not suitable to battle, and the config disallows replacing it")
        end
    
        print("Lead Pokemon is not suitable to battle. Replacing...")

        local replacement

        for i, ally in ipairs(party) do
            if is_healthy(ally) then
                replacement = i
                break
            end
        end

        if not replacement then
            abort("No suitable Pokemon left to battle")
        end

        print("Next replacement is " .. party[replacement].name .. " (Slot " .. replacement .. ")")

        -- Step 40: keep the original switching routine unchanged, but allow
        -- Platinum six seconds to settle before any switching/menu inputs.
        clear_all_inputs()
        wait_frames(360)
        clear_all_inputs()

        open_menu("Pokemon")
        
        -- Highlight lead
        local i = 1
        while i ~= get_lead_mon_index() do
            press_sequence("Right", 5)
            i = i + 1
        end

        -- Switch
        press_sequence("A", 30, "Up", 8, "Up", 8, "Up", 8, "A", 30)
        
        -- Highlight replacement
        local i = 1
        while i ~= replacement do
            press_sequence("Right", 5)
            i = i + 1
        end

        press_sequence("A", 30, "B", 120, "B", 120, "B", 30) -- Exit out of menu
    end

    if config.thief_wild_items then
        -- Check leading Pokemon for held items
        local lead = get_lead_mon_index()

        if party[lead].heldItem ~= "none" and pokemon.get_move_slot(party[lead], "Thief") ~= 0 then
            print("Thief Pokemon already holds an item. Removing...")

            -- Step 48: after a battle, D/P/Pt can report that the battle has ended
            -- before overworld/menu input is actually safe.  If we try to open the
            -- Pokemon menu during that transition, X can be ignored and open_menu()
            -- can end up repeatedly sending a direction in the overworld.
            -- Reuse the same six-second settling period already proven reliable by
            -- the Step 40 post-battle lead-switch routine.
            clear_all_inputs()
            if _ROM.version == "D" or _ROM.version == "P" or _ROM.version == "PL" then
                wait_frames(360)
            end
            clear_all_inputs()

            open_menu("Pokemon")
            
            local i = 1
            while i ~= lead do
                press_sequence("Right", 5)
                i = i + 1
            end
            
            -- Take item
            press_sequence("A", 8, "Up", 8, "Up", 8, "A", 22, "Down", 8, "A")
            wait_frames(90)
            press_button("B")
            
            press_sequence(30, "B", 120, "B", 60) -- Exit out of menu
        end
    end
end

--- Moves the bot toward a position on the map
-- @param target Target position (x, z)
-- @param on_move Function called each frame while moving
function move_to(target, on_move)
    if target.x then
        target.x = target.x + 0.5

        while game_state.trainer_x < target.x - 0.5 do
            hold_button("Right")
            if on_move then on_move() end
        end
        
        while game_state.trainer_x > target.x + 0.5 do
            hold_button("Left")
            if on_move then on_move() end
        end
    end

    if target.z then
        target.z = target.z + 0.5
        
        while game_state.trainer_z < target.z - 0.5 do
            hold_button("Down")
            if on_move then on_move() end
        end
        
        while game_state.trainer_z > target.z + 0.5 do
            hold_button("Up")
            if on_move then on_move() end
        end
    end
end

-- Same as above essentially, but won't gradually move the player off course
function move_to_fixed(target)
    while game_state.trainer_x < target.x do
        hold_button("Right")
    end

    while game_state.trainer_x > target.x do
        hold_button("Left")
    end

    while game_state.trainer_z < target.z do
        hold_button("Down")
    end

    while game_state.trainer_z > target.z do
        hold_button("Up")
    end
end

--- General script for receiving and checking multiple gift Pokemon types
function mode_gift()
    if not game_state.in_game then
        print("Waiting to reach overworld...")

        while not game_state.in_game do
            progress_text()
        end
    end

    local og_party_count = #party
    while #party == og_party_count do
        progress_text()
    end

    local mon = party[#party]
    local is_target = pokemon.log_encounter(mon)

    if is_target then
        abort(mon.name .. " is a target!")
    else
        print(mon.name .. " was not a target, resetting...")
        soft_reset()
    end
end

--- Resets until the encountered overworld Pokemon is a target
function mode_static_encounters()
    while not game_state.in_battle do
        if game_state.map_name == "Dreamyard" then
            hold_button("Right")
        elseif game_state.map_name == "Spear Pillar" then
            hold_button("Up")
        end

        progress_text()
    end

    local mon = foe[1]
    local is_target = pokemon.log_encounter(mon)

    if is_target then
        if config.auto_catch then
            while game_state.in_battle do
                catch_pokemon()
            end

            abort("Target " .. mon.name .. " was caught!")
        else
            abort(mon.name .. " is a target!")
        end
    else
        print(mon.name .. " was not a target, resetting...")
        soft_reset()
    end
end

--- Presses the RUN button until the battle is over
function flee_battle()
    while game_state.in_battle do
        touch_screen_at(125, 175)
        wait_frames(5)
    end

    print("Got away safely!")
end

--- Progress text with imperfect inputs to increase the randomness of frames hit
function progress_text()
    hold_button("A")
    wait_frames(math.random(5, 20))
    release_button("A")
    wait_frames(5)
end
