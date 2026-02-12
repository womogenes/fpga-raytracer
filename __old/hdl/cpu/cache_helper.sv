`default_nettype none

// Cache geometry
parameter integer cache_sets = 64;
parameter integer words_per_line = 16;

// Log values of parameters
parameter integer log_cache_sets = $clog2(cache_sets);
parameter integer log_words_per_line = $clog2(words_per_line);

// Data types
typedef logic [words_per_line-1:0] CacheLine [4];

// Cache types
typedef logic [1:0] ByteOffset;

`default_nettype wire
