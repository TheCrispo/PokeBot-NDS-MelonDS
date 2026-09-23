-----------------------------------------------------------------------------
-- Bot method overrides for Platinum
-- Author: wyanido
-- Homepage: https://github.com/wyanido/pokebot-nds
-----------------------------------------------------------------------------

function update_pointers()
    local anchor = mdword(0x21C0794 + _ROM.offset)
	local foe_anchor = mdword(anchor + 0x217A8)
    
	pointers = {
        start_value = 0x2101008, -- 0 until save has been loaded
		party_count = anchor + 0xB0,
		party_data  = anchor + 0xB4,

		foe_count 	= foe_anchor - 0x2D5C,
		current_foe = foe_anchor - 0x2D58,
		
		map_header	= anchor + 0x1294,
        menu_option = 0x21C4C86 + _ROM.offset,
		trainer_x   = 0x21C5CE4 + _ROM.offset,
        trainer_y   = 0x21C5CE8 + _ROM.offset,
        trainer_z   = 0x21C5CEC + _ROM.offset,
		facing		= anchor + 0x238A4,
		
        bike_gear = anchor + 0x1320,
        bike      = anchor + 0x1324,
        
        daycare_egg = anchor + 0x1840,

        selected_starter = anchor + 0x41850,
        starters_ready   = anchor + 0x418D4,

		battle_menu_state      = anchor + 0x44878, -- 01 is FIGHT menu, 04 is Move Select, 08 is Bag,
		battle_menu_state2     = anchor + 0x7E282,
		battle_indicator       = 0x021D18F2 + _ROM.offset,
        fishing_bite_indicator = 0x021CF636 + _ROM.offset,

        trainer_name = anchor + 0x7C,
        trainer_id   = anchor + 0x8C,

        roamer = mdword(anchor + 0x28364),
        _anchor = anchor,
	}
end

-- Platinum does not expose the generic Gen IV bag pointers used by gen_iv.lua.
-- Locate the 15-slot Poké Ball pocket dynamically inside Platinum's player heap.
local platinum_ball_pocket = nil

local function get_configured_ball_ids()
    local ids = {}
    for id = 1, 16 do
        local name = _ITEM[id + 1]
        if name then
            local lname = string.lower(name)
            if config and config.pokeball_priority then
                for _, wanted in ipairs(config.pokeball_priority) do
                    if string.lower(wanted) == lname then ids[id] = true end
                end
            end
            if config and config.pokeball_override then
                for wanted, _ in pairs(config.pokeball_override) do
                    if string.lower(wanted) == lname then ids[id] = true end
                end
            end
        end
    end
    return ids
end

local function find_platinum_ball_pocket()
    if platinum_ball_pocket then return platinum_ball_pocket end
    local anchor = pointers and pointers._anchor
    if not anchor or anchor == 0 then return nil end

    local wanted = get_configured_ball_ids()
    local best_addr, best_score, best_found = nil, -1, 0
    local ram_start = 0x02000000
    local ram_end = 0x02400000 - 0x3C

    for addr = ram_start, ram_end, 4 do
        local first = mword(addr)
        if first <= 16 then
            local valid, ball_count, wanted_count, empty_count = true, 0, 0, 0
            for slot = 0, 14 do
                local item = mword(addr + slot * 4)
                local count = mword(addr + slot * 4 + 2)
                if item > 16 or count > 999 then
                    valid = false
                    break
                end
                if item == 0 and count == 0 then
                    empty_count = empty_count + 1
                elseif item >= 1 and item <= 16 and count > 0 then
                    ball_count = ball_count + 1
                    if wanted[item] then wanted_count = wanted_count + 1 end
                else
                    valid = false
                    break
                end
            end
            if valid and ball_count > 0 then
                local score = wanted_count * 1000 + ball_count * 10 + empty_count
                if score > best_score then
                    best_addr, best_score, best_found = addr, score, wanted_count
                end
            end
        end
    end

    if best_addr then
        platinum_ball_pocket = best_addr
        print_debug(string.format("Platinum Poke Ball pocket found at 0x%08X (configured balls found: %d)", best_addr, best_found))
    else
        print_debug("Could not locate the Platinum Poke Ball pocket in main RAM")
    end
    return platinum_ball_pocket
end

function get_usable_balls()
    local balls = {}
    local base = find_platinum_ball_pocket()
    if not base then return balls end
    local slot = 0
    for i = base, base + 0x38, 4 do
        local count = mword(i + 2)
        if count > 0 then
            local id = mword(i)
            local item_name = _ITEM[id + 1]
            if item_name then
                balls[string.lower(item_name)] = slot + 1
                print_debug(string.format("Poke Ball detected: %s x%d (slot %d)", item_name, count, slot + 1))
            end
        end
        slot = slot + 1
    end
    return balls
end
