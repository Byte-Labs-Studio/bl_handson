---@alias HandsonStepKind 'click' | 'drag' | 'turn' | 'adjust' | 'torque' | 'pick' | 'pump'

---@class HandsonStep
---@field name string
---@field kind HandsonStepKind
---@field view string
---@field label string
---@field hint string
---@field minMs integer
---@field target? string
---@field tool? 'ratchet' | 'breaker' | 'torque'
---@field dir? 1 | -1
---@field turns? number
---@field breakaway? boolean
---@field reverse? boolean
---@field side? 1 | -1
---@field goal? 'loose' | 'set'

---@class BikeWheelSpec
---@field torque number
---@field breakaway number
---@field pumps integer
---@field slackBase number
---@field slackPerTurn number
---@field slackLo number
---@field slackHi number
---@field skew number
---@field looseTurns number
---@field alignTolerance number

local config = require 'config'

local bikewheel = {}

bikewheel.wheels = {
    front = { bone = 'wheel_lf', wheelIndex = 1, tyreIndex = 0, item = config.items.frontWheel, thickSide = -1 },
    rear = { bone = 'wheel_lr', wheelIndex = 0, tyreIndex = 4, item = config.items.rearWheel, thickSide = -1 },
}

---@type table<string, HandsonStep[]>
bikewheel.steps = {
    rear = {
        { name = 'stand_lift', kind = 'drag', view = 'stand', target = 'stand_handle', minMs = 1200, label = 'Lift the bike', hint = 'Drag the paddock stand handle down until the rear wheel is off the ground.' },
        { name = 'caliper_bolt_1', kind = 'turn', view = 'caliper', target = 'caliper_bolt_1', tool = 'ratchet', dir = -1, turns = 3, minMs = 1800, label = 'Undo the top caliper bolt', hint = 'Hold the bolt and circle anticlockwise.' },
        { name = 'caliper_bolt_2', kind = 'turn', view = 'caliper', target = 'caliper_bolt_2', tool = 'ratchet', dir = -1, turns = 3, minMs = 1800, label = 'Undo the lower caliper bolt', hint = 'Hold the bolt and circle anticlockwise.' },
        { name = 'caliper_off', kind = 'drag', view = 'caliper', target = 'caliper', minMs = 900, label = 'Lift the caliper off', hint = 'Drag the caliper up off the disc and let it hang.' },
        { name = 'axle_nut_off', kind = 'turn', view = 'nut', target = 'axle_nut', tool = 'breaker', dir = -1, turns = 3, breakaway = true, minMs = 2200, label = 'Undo the axle nut', hint = 'Lean on the breaker bar anticlockwise until it cracks, then keep turning.' },
        { name = 'adjusters_loose', kind = 'adjust', view = 'rear', goal = 'loose', minMs = 2000, label = 'Back off the chain adjusters', hint = 'Hold each adjuster and circle anticlockwise until both bars are full.' },
        { name = 'axle_out', kind = 'drag', view = 'head', target = 'axle', minMs = 1000, label = 'Pull the axle', hint = 'Drag the axle out of the swingarm.' },
        { name = 'chain_off', kind = 'drag', view = 'nut', target = 'wheel_forward', minMs = 800, label = 'Slip the chain off', hint = 'Push the wheel forward so the chain drops off the sprocket.' },
        { name = 'wheel_out', kind = 'drag', view = 'wide', target = 'wheel_out', minMs = 1000, label = 'Roll the old wheel out', hint = 'Drag the wheel down and back out of the swingarm.' },
        { name = 'wheel_in', kind = 'drag', view = 'wide', target = 'wheel_in', minMs = 1200, label = 'Fit the new wheel', hint = 'Lift the new wheel up into the swingarm.' },
        { name = 'chain_on', kind = 'click', view = 'nut', target = 'chain', minMs = 500, label = 'Hook the chain on', hint = 'Click the chain to loop it over the sprocket.' },
        { name = 'spacer_left', kind = 'pick', view = 'nut', side = -1, minMs = 600, label = 'Fit the sprocket-side spacer', hint = 'The thick spacer sits on the sprocket side. Pick one.' },
        { name = 'spacer_right', kind = 'pick', view = 'head', side = 1, minMs = 600, label = 'Fit the disc-side spacer', hint = 'Pick the spacer for the disc side.' },
        { name = 'axle_in', kind = 'drag', view = 'head', target = 'axle', reverse = true, minMs = 1000, label = 'Slide the axle through', hint = 'Push the axle back through the swingarm and wheel.' },
        { name = 'axle_nut_on', kind = 'turn', view = 'nut', target = 'axle_nut', dir = 1, turns = 3, minMs = 1500, label = 'Run the nut on', hint = 'Circle clockwise to spin the nut on by hand.' },
        { name = 'adjusters_set', kind = 'adjust', view = 'rear', goal = 'set', minMs = 2500, label = 'Set the chain slack', hint = 'Turn the adjusters until slack is in the green and both marks match, then press E.' },
        { name = 'axle_torque', kind = 'torque', view = 'nut', target = 'axle_nut', tool = 'torque', minMs = 1500, label = 'Torque the axle nut', hint = 'Circle clockwise and let go when the wrench clicks. Over spec? Circle anticlockwise to back it off.' },
        { name = 'caliper_on', kind = 'drag', view = 'caliper', target = 'caliper', reverse = true, minMs = 900, label = 'Refit the caliper', hint = 'Drag the caliper back over the disc.' },
        { name = 'caliper_tighten_1', kind = 'turn', view = 'caliper', target = 'caliper_bolt_1', tool = 'ratchet', dir = 1, turns = 3, minMs = 1800, label = 'Tighten the top caliper bolt', hint = 'Circle clockwise.' },
        { name = 'caliper_tighten_2', kind = 'turn', view = 'caliper', target = 'caliper_bolt_2', tool = 'ratchet', dir = 1, turns = 3, minMs = 1800, label = 'Tighten the lower caliper bolt', hint = 'Circle clockwise.' },
        { name = 'brake_pump', kind = 'pump', view = 'brake', target = 'brake', minMs = 1200, label = 'Pump the brake', hint = 'Click the brake pedal until it goes firm.' },
        { name = 'stand_lower', kind = 'drag', view = 'stand', target = 'stand_handle', reverse = true, minMs = 1000, label = 'Lower the bike', hint = 'Ease the stand handle back up to set the bike down.' },
    },

    front = {
        { name = 'stand_lift', kind = 'drag', view = 'stand', target = 'stand_handle', minMs = 1200, label = 'Lift the front', hint = 'Drag the fork stand handle down until the front wheel is off the ground.' },
        { name = 'caliper_bolt_1', kind = 'turn', view = 'caliper', target = 'caliper_bolt_1', tool = 'ratchet', dir = -1, turns = 3, minMs = 1800, label = 'Undo the top caliper bolt', hint = 'Hold the bolt and circle anticlockwise.' },
        { name = 'caliper_bolt_2', kind = 'turn', view = 'caliper', target = 'caliper_bolt_2', tool = 'ratchet', dir = -1, turns = 3, minMs = 1800, label = 'Undo the lower caliper bolt', hint = 'Hold the bolt and circle anticlockwise.' },
        { name = 'caliper_off', kind = 'drag', view = 'caliper', target = 'caliper', minMs = 900, label = 'Pull the caliper off', hint = 'Drag the caliper back off the disc and let it hang.' },
        { name = 'axle_nut_off', kind = 'turn', view = 'nut', target = 'axle_nut', tool = 'breaker', dir = -1, turns = 3, breakaway = true, minMs = 2200, label = 'Undo the axle nut', hint = 'Lean on the breaker bar anticlockwise until it cracks, then keep turning.' },
        { name = 'axle_out', kind = 'drag', view = 'head', target = 'axle', minMs = 1000, label = 'Pull the axle', hint = 'Drag the axle out of the fork legs.' },
        { name = 'wheel_out', kind = 'drag', view = 'wide', target = 'wheel_out', minMs = 1000, label = 'Drop the old wheel out', hint = 'Drag the wheel down and forward out of the forks.' },
        { name = 'wheel_in', kind = 'drag', view = 'wide', target = 'wheel_in', minMs = 1200, label = 'Fit the new wheel', hint = 'Lift the new wheel up between the fork legs.' },
        { name = 'spacer_left', kind = 'pick', view = 'nut', side = -1, minMs = 600, label = 'Fit the left spacer', hint = 'The thick spacer sits opposite the disc. Pick one.' },
        { name = 'spacer_right', kind = 'pick', view = 'head', side = 1, minMs = 600, label = 'Fit the disc-side spacer', hint = 'Pick the spacer for the disc side.' },
        { name = 'axle_in', kind = 'drag', view = 'head', target = 'axle', reverse = true, minMs = 1000, label = 'Slide the axle through', hint = 'Push the axle back through the forks and wheel.' },
        { name = 'axle_nut_on', kind = 'turn', view = 'nut', target = 'axle_nut', dir = 1, turns = 3, minMs = 1500, label = 'Run the nut on', hint = 'Circle clockwise to spin the nut on by hand.' },
        { name = 'axle_torque', kind = 'torque', view = 'nut', target = 'axle_nut', tool = 'torque', minMs = 1500, label = 'Torque the axle nut', hint = 'Circle clockwise and let go when the wrench clicks. Over spec? Circle anticlockwise to back it off.' },
        { name = 'caliper_on', kind = 'drag', view = 'caliper', target = 'caliper', reverse = true, minMs = 900, label = 'Refit the caliper', hint = 'Drag the caliper back over the disc.' },
        { name = 'caliper_tighten_1', kind = 'turn', view = 'caliper', target = 'caliper_bolt_1', tool = 'ratchet', dir = 1, turns = 3, minMs = 1800, label = 'Tighten the top caliper bolt', hint = 'Circle clockwise.' },
        { name = 'caliper_tighten_2', kind = 'turn', view = 'caliper', target = 'caliper_bolt_2', tool = 'ratchet', dir = 1, turns = 3, minMs = 1800, label = 'Tighten the lower caliper bolt', hint = 'Circle clockwise.' },
        { name = 'brake_pump', kind = 'pump', view = 'brake', target = 'brake', minMs = 1200, label = 'Pump the brake lever', hint = 'Click the brake lever until it goes firm.' },
        { name = 'stand_lower', kind = 'drag', view = 'stand', target = 'stand_handle', reverse = true, minMs = 1000, label = 'Lower the bike', hint = 'Ease the stand handle back up to set the bike down.' },
    },
}

---@param spec BikeWheelSpec
---@param left number
---@param right number
---@return number slack mm
---@return number skew turns
function bikewheel.chain(spec, left, right)
    return spec.slackBase - spec.slackPerTurn * ((left + right) * 0.5), (right - left) + spec.skew
end

return bikewheel
