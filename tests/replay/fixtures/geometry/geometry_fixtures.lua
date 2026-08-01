local PI = math.pi

return {
    {
        fixture_id = "geometry_normalize_zero",
        helper = "normalize_angle_rad",
        description = "zero angle remains zero",
        input = {
            angle = 0,
        },
        expected = {
            result = 0,
        },
    },
    {
        fixture_id = "geometry_normalize_over_pi_wraps_negative",
        helper = "normalize_angle_rad",
        description = "angle greater than pi wraps into negative range",
        input = {
            angle = PI + 0.1,
        },
        expected = {
            result = -PI + 0.1,
        },
    },
    {
        fixture_id = "geometry_normalize_under_negative_pi_wraps_positive",
        helper = "normalize_angle_rad",
        description = "angle less than -pi wraps into positive range",
        input = {
            angle = -PI - 0.2,
        },
        expected = {
            result = PI - 0.2,
        },
    },
    {
        fixture_id = "geometry_normalize_exact_pi_unchanged",
        helper = "normalize_angle_rad",
        description = "exact pi is unchanged",
        input = {
            angle = PI,
        },
        expected = {
            result = PI,
        },
    },
    {
        fixture_id = "geometry_normalize_exact_negative_pi_unchanged",
        helper = "normalize_angle_rad",
        description = "exact -pi is unchanged",
        input = {
            angle = -PI,
        },
        expected = {
            result = -PI,
        },
    },
    {
        fixture_id = "geometry_front_arc_target_straight_ahead_true",
        helper = "target_is_in_front_arc",
        description = "target directly ahead is inside default front arc",
        input = {
            me = { x = 0, y = 0, facing = 0 },
            target = { x = 10, y = 0 },
            arc = nil,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "geometry_front_arc_target_behind_false",
        helper = "target_is_in_front_arc",
        description = "target directly behind is outside default front arc",
        input = {
            me = { x = 0, y = 0, facing = 0 },
            target = { x = -10, y = 0 },
            arc = nil,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "geometry_front_arc_boundary_true",
        helper = "target_is_in_front_arc",
        description = "target exactly on arc boundary is included",
        input = {
            me = { x = 0, y = 0, facing = 0 },
            target = { x = 0, y = 10 },
            arc = PI / 2,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "geometry_front_arc_narrow_excludes_side_target",
        helper = "target_is_in_front_arc",
        description = "narrow arc excludes side target",
        input = {
            me = { x = 0, y = 0, facing = 0 },
            target = { x = 0, y = 10 },
            arc = PI / 4,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "geometry_front_arc_missing_me_returns_false",
        helper = "target_is_in_front_arc",
        description = "missing me data returns false",
        input = {
            me = nil,
            target = { x = 1, y = 0 },
            arc = PI / 2,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "geometry_front_arc_missing_target_returns_false",
        helper = "target_is_in_front_arc",
        description = "missing target returns false",
        input = {
            me = { x = 0, y = 0, facing = 0 },
            target = nil,
            arc = PI / 2,
        },
        expected = {
            result = false,
        },
    },
}
