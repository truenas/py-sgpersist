# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

from libc.stdint cimport uint8_t, uint32_t

cdef extern from "scsi/sg_lib.h" nogil:

    uint8_t * sg_memalign(uint32_t, uint32_t, uint8_t**, bint)
