# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

from libc.stdint cimport uint32_t, uint64_t

cdef extern from "scsi/sg_unaligned.h" nogil:

    uint32_t sg_get_unaligned_be32(const void* p)
    uint64_t sg_get_unaligned_be64(const void* p)
    void sg_put_unaligned_be64(uint64_t, void* p)
