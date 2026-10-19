return {
    items = {
        toolkit = 'moto_toolkit',
        frontWheel = 'moto_wheel_front',
        rearWheel = 'moto_wheel_rear',
    },

    ---@type 'auto' | 'none' | 'ox_inventory' | 'qs-inventory' | 'qb-core' | 'es_extended'
    inventory = 'auto',

    requireItems = true,

    ---@type 'auto' | 'none' | 'ox_target' | 'qb-target'
    target = 'auto',

    command = {
        enabled = false,
        name = 'changewheel',
        distance = 3.0,
        ---@type false | string
        ace = false,
    },

    interactDistance = 1.8,
    maxStrikes = 3,
}
