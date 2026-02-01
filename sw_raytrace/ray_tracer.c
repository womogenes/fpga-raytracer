#include <stdlib.h>

#include "types.h"
#include "prng.h"

#include "ray_intersector.c"
#include "ray_reflector.c"

#define MAX_BOUNCES 5

void ray_tracer(RayTracerParams* params, RayTracerResult* result) {
  Vec3 ray_pos = params->ray_origin;
  Vec3 ray_dir = params->ray_dir;
  Color ray_color = (Color){ 1, 1, 1 };
  Color income_light = (Color){ 0, 0, 0 };

  // Seed the LFSR
  int pixel_h = params->pixel_h;
  int pixel_v = params->pixel_v;

  rand0 += (pixel_h * 1009) ^ (pixel_v * 2003);
  rand1 += (pixel_h * 2003) ^ (pixel_v * 4001);
  rand2 += (pixel_h * 4001) ^ (pixel_v * 1009);

  // Trace the ray
  RayIntersectorResult hit_result;
  RayReflectorResult ref_result;

  int any_hit = 0;

  for (int bounce_idx = 0; bounce_idx < MAX_BOUNCES; bounce_idx++) {
    ray_intersector(ray_dir, ray_pos, &hit_result);
    ray_pos = hit_result.hit_pos;
    any_hit |= hit_result.any_hit;

    if (!hit_result.any_hit) {
      // Ray flew off into the distance, add ambient light
      Color ambient = (Color){0, 0, 0};
      income_light = add_vec3c(income_light, mul_vec3c(ambient, ray_color));
      break;
    }

    ray_reflector(&ray_pos, &ray_dir, &hit_result.hit_norm, &ray_color, &income_light, &hit_result.hit_mat);
  }

  if (any_hit) {
    result->pixel_color = (Color){
      .r = min(income_light.r, 1) * 255,
      .g = min(income_light.g, 1) * 255,
      .b = min(income_light.b, 1) * 255,
    };

  } else {
    // By default, if the ray didn't hit anything, render grey
    result->pixel_color = (Color){
      .r = 32,
      .b = 32,
      .g = 32,
    };
  }

  result->pixel_h = params->pixel_h;
  result->pixel_v = params->pixel_v;
}
