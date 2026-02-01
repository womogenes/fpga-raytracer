
// Top-level renderer

#include <stdio.h>
#include <stdint.h>

#include "types.h"
#include "utils.h"

#include "ray_caster.c"
#include "ray_tracer.c"

uint8_t fb[HEIGHT][WIDTH][3];
float fb_float[HEIGHT][WIDTH][3];

int main() {
  Camera cam = (Camera){
    .origin  = {0, 0, -10},
    .forward = {0, WIDTH / 2 * 2.28, 0},
    .right = {WIDTH / 2, 0, 0},
    .up = {0, 0, HEIGHT / 2},
  };
  
  RayTracerParams params;
  RayTracerResult result;

  const int N_FRAMES = 1;
  const int mask_565 = 0;

  for (int frame_idx = 0; frame_idx < N_FRAMES; frame_idx++) {
    printf("rendering frame %d\n", frame_idx);

    for (int pixel_v = 0; pixel_v < HEIGHT; pixel_v++) {
      for (int pixel_h = 0; pixel_h < WIDTH; pixel_h++) {
        ray_caster(&cam, pixel_h, pixel_v, &params);
        ray_tracer(&params, &result);

        uint8_t r_mask = mask_565 ? 0b11111000 : 0xFF;
        uint8_t g_mask = mask_565 ? 0b11111000 : 0xFF;
        uint8_t b_mask = mask_565 ? 0b11111000 : 0xFF;

        fb_float[pixel_v][pixel_h][0] += (uint8_t)result.pixel_color.r & r_mask;
        fb_float[pixel_v][pixel_h][1] += (uint8_t)result.pixel_color.g & g_mask;
        fb_float[pixel_v][pixel_h][2] += (uint8_t)result.pixel_color.b & b_mask;

        // uint8_t* pix_r = &(fb[pixel_v][pixel_h][0]);
        // uint8_t* pix_g = &(fb[pixel_v][pixel_h][1]);
        // uint8_t* pix_b = &(fb[pixel_v][pixel_h][2]);

        // *pix_r = t * (*pix_r) + (1 - t) * result.pixel_color.r;
        // *pix_g = t * (*pix_g) + (1 - t) * result.pixel_color.g;
        // *pix_b = t * (*pix_b) + (1 - t) * result.pixel_color.b;
      }
    }

    for (int pixel_v = 0; pixel_v < HEIGHT; pixel_v++) {
      for (int pixel_h = 0; pixel_h < WIDTH; pixel_h++) {
        for (int channel = 0; channel < 3; channel++) {
          fb[pixel_v][pixel_h][channel] = fb_float[pixel_v][pixel_h][channel] / N_FRAMES;
        }
      }
    }
  }

  int32_t a = 0xFFFFFFFF;
  int32_t b = 0xFFFFFFFF;
  int32_t res = mul16(a, b);
  printf("prod = 0x%x\n", res);

  FILE* f = fopen("image.bin", "wb");
  fwrite(fb, 3, WIDTH * HEIGHT, f);
  fclose(f);
}
