// Needs to be defined here because proc_types.sv uses MemFunc etc.
typedef logic [31:0] Word;

typedef enum logic [2:0] { LW, LH, LHU, LB, LBU, SW, SH, SB } MemFunc;

function logic is_store(input MemFunc mem_func);
  return (mem_func == SW) || (mem_func == SH) || (mem_func == SB);
endfunction

function logic is_load(input MemFunc mem_func); 
  return (mem_func == LW) || (mem_func == LH) || (mem_func == LHU) || (mem_func == LB) || (mem_func == LBU);
endfunction

typedef struct packed {
  MemFunc op;
  Word addr;
  Word data;
} MemReq;

// Cache geometry
parameter integer CACHE_SETS = 64;
parameter integer WORDS_PER_LINE = 16;

parameter integer LOG_CACHE_SETS = $clog2(CACHE_SETS);
parameter integer LOG_WORDS_PER_LINE = $clog2(WORDS_PER_LINE);

// Data types
typedef Word Line [WORDS_PER_LINE-1:0];

// Address types
typedef logic [1:0] ByteOffset;
typedef logic [LOG_CACHE_SETS-1:0] CacheIndex;
typedef logic [LOG_WORDS_PER_LINE-1:0] WordOffset;

// tag size + index size + word offset size + byte offset size = 32
// With the default values, the tag size is 32 - 6 (index size) - 4 (word offset size) - 2 (byte offset size) = 20
typedef logic [31-LOG_CACHE_SETS-LOG_WORDS_PER_LINE-2:0] CacheTag;

// The line address is just the portion of the byte address used to select lines from main memory.
// The line address is equal to the tag and index concatenated together
typedef logic [31-LOG_WORDS_PER_LINE-2:0] LineAddr;

// Status for each line
typedef enum logic [1:0] { NOT_VALID = 2'b10, CLEAN = 2'b00, DIRTY = 2'b01 } CacheStatus;

// TaggedLine is combo of data, tag, status of cache line
typedef struct packed {
  Line line;
  CacheStatus status;
  CacheTag tag;
} TaggedLine;

// RequestStatus used to keep track of state of current request
typedef enum logic [2:0] {
  READY,
  LOOKUP,
  WRITEBACK,
  FILL
} RequestStatus;

// Cache SRAM type synonyms
