# RTX-specific net constraints
# Keep pin/IO constraints in `xdc/top_level.xdc`

# Allow combinational loop for ring oscillator RNG
# TODO: clean this up / make less hierarchy-fragile
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[3].n1]

