package.path = './?.lua;' .. package.path

local runtime = require('uc_smn_runtime')

local function assert_close(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error(('%s: expected %.6f, got %.6f'):format(message, expected, actual))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
    end
end

local edge, center, pet_size, target_size = runtime.pet_distance(
    { x = 0, y = 0, model_size = 1.2 },
    { x = 6.7, y = 0, model_size = 3.4 }
)
assert_close(center, 6.7, 0.000001, 'center distance')
assert_close(edge, 2.1, 0.000001, 'model-edge distance')
assert_close(pet_size, 1.2, 0.000001, 'pet model size')
assert_close(target_size, 3.4, 0.000001, 'target model size')

edge, center = runtime.pet_distance(
    { x = 0, y = 0, model_size = 2.0 },
    { x = 1, y = 0, model_size = 2.0 }
)
assert_close(center, 1.0, 0.000001, 'overlap center distance')
assert_equal(edge, 0, 'overlapping model edges clamp to zero')

edge, center = runtime.pet_distance(
    { x = 0, y = 0 },
    { x = 3, y = 4 }
)
assert_close(center, 5.0, 0.000001, 'missing-size center distance')
assert_close(edge, 5.0, 0.000001, 'missing sizes preserve center distance')

print('selftest_smn_pet_distance: OK')
