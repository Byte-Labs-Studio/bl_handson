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

    prompt = {
        key = 'E',
        distance = 1.8,
    },

    ---@type false | { name: string, restricted: false | string | string[] }
    command = false,

    interactDistance = 1.8,
    maxStrikes = 3,
}
