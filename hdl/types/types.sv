parameter integer FRAC_WIDTH = 16;
parameter integer FULL_WIDTH = 32;

// ===== NUMBERS + MATH =====

// NOTE: declaration of fp moved to constants.sv because dependencies

// ===== COLORS =====
typedef struct packed {
  logic [7:0] r;
  logic [7:0] g;
  logic [7:0] b;
} color8;

typedef struct packed {
  fp r;
  fp g;
  fp b;
} fp_color;

// ===== VECTOR TYPES =====
typedef struct packed {
  fp x;
  fp y;
  fp z;
} fp_vec3;

// ===== CAMERA =====
typedef struct packed {
  fp_vec3 origin;
  fp_vec3 forward;
  fp_vec3 right;
  fp_vec3 up;
} camera;

// ===== OBJECTS =====
typedef struct packed {
  fp_color color;
  fp_color emit_color;
  fp_color spec_color;
  fp smoothness;
  fp one_sub_smoothness;
  logic [7:0] specular_prob;  // 8 bits
} material;

typedef struct packed {
  logic [1:0] obj_type;             // 0: sphere, 1: trig, 2: parallelogram, 3: plane
  logic [7:0] mat_idx;              // [several] bits
  logic [(FP_BITS*12)-1:0] stuff;   // max data needed for object geometry (288)
} object;

typedef struct packed {
  fp_vec3 sphere_center;  // 72 bits
  fp sphere_rad_sq;       // 24 bits
  fp sphere_rad_inv;      // 24 bits
  logic [(FP_BITS*7)-1:0] stuff;      // throwaway 168 bits
} sphere;

typedef struct packed {
  fp_vec3 [2:0] points;    // 216 bits
  fp_vec3 normal;          // 72 bits
} trig;
