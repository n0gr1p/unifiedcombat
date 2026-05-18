local function write_u16_le(bytes, offset_1_based, value)
    local v = value or 0
    bytes[offset_1_based] = v % 256
    bytes[offset_1_based + 1] = math.floor(v / 256) % 256
end

local function write_u32_le(bytes, offset_1_based, value)
    local v = value or 0
    bytes[offset_1_based] = v % 256
    bytes[offset_1_based + 1] = math.floor(v / 256) % 256
    bytes[offset_1_based + 2] = math.floor(v / 65536) % 256
    bytes[offset_1_based + 3] = math.floor(v / 16777216) % 256
end

local function make_packet(opcode_byte_5, buffs, endtimes)
    local bytes = {}
    local packet_len = 220
    for i = 1, packet_len do
        bytes[i] = 0
    end
    bytes[5] = opcode_byte_5 or 0

    for n = 1, 32 do
        local buff_id = buffs[n] or 0
        local endtime = endtimes[n] or 0

        local buff_offset = n * 2 + 7
        local endtime_offset = n * 4 + 71
        write_u16_le(bytes, buff_offset, buff_id)
        write_u32_le(bytes, endtime_offset, endtime)
    end

    local out = {}
    for i = 1, packet_len do
        out[i] = string.char(bytes[i])
    end
    return table.concat(out)
end

return {
    {
        fixture_id = "status063_invalid_non_string",
        description = "non-string input must return nil",
        tags = { "parser", "status063", "invalid" },
        data = false,
        expected = nil,
    },
    {
        fixture_id = "status063_invalid_too_short",
        description = "short payload (<80 bytes) must return nil",
        tags = { "parser", "status063", "invalid" },
        data = string.rep("\0", 79),
        expected = nil,
    },
    {
        fixture_id = "status063_invalid_opcode",
        description = "byte 5 different from 9 must return nil",
        tags = { "parser", "status063", "gate" },
        data = make_packet(8, { 255 }, { 0 }),
        expected = nil,
    },
    {
        fixture_id = "status063_empty_sentinel_first",
        description = "first buff sentinel (255) returns empty status map",
        tags = { "parser", "status063", "sentinel" },
        data = make_packet(9, { 255 }, { 0 }),
        expected = {},
    },
    {
        fixture_id = "status063_single_buff_no_endtime",
        description = "single buff with zero endtime tracks count only",
        tags = { "parser", "status063", "count" },
        data = make_packet(9, { 123, 255 }, { 0, 0 }),
        expected = {
            [123] = { count = 1, endtimes = {} },
        },
    },
    {
        fixture_id = "status063_duplicate_buff_sorted_endtimes",
        description = "duplicate buff ids aggregate count and sort endtimes",
        tags = { "parser", "status063", "sort" },
        data = make_packet(9, { 50, 50, 255 }, { 30, 10, 0 }),
        expected = {
            [50] = { count = 2, endtimes = { 10, 30 } },
        },
    },
    {
        fixture_id = "status063_multi_buff_mixed_endtimes",
        description = "multiple buffs with mixed zero/nonzero endtimes",
        tags = { "parser", "status063", "multi" },
        data = make_packet(9, { 1, 2, 1, 255 }, { 0, 99, 77, 0 }),
        expected = {
            [1] = { count = 2, endtimes = { 77 } },
            [2] = { count = 1, endtimes = { 99 } },
        },
    },
    {
        fixture_id = "status063_full_32_no_sentinel",
        description = "no sentinel in first 32 entries consumes all slots",
        tags = { "parser", "status063", "full-scan" },
        data = make_packet(
            9,
            {
                1, 1, 1, 1, 1, 1, 1, 1,
                1, 1, 1, 1, 1, 1, 1, 1,
                1, 1, 1, 1, 1, 1, 1, 1,
                1, 1, 1, 1, 1, 1, 1, 1,
            },
            {
                32, 31, 30, 29, 28, 27, 26, 25,
                24, 23, 22, 21, 20, 19, 18, 17,
                16, 15, 14, 13, 12, 11, 10, 9,
                8, 7, 6, 5, 4, 3, 2, 1,
            }
        ),
        expected = {
            [1] = {
                count = 32,
                endtimes = {
                    1, 2, 3, 4, 5, 6, 7, 8,
                    9, 10, 11, 12, 13, 14, 15, 16,
                    17, 18, 19, 20, 21, 22, 23, 24,
                    25, 26, 27, 28, 29, 30, 31, 32,
                },
            },
        },
    },
}
