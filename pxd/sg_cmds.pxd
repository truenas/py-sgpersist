# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

cdef extern from "scsi/sg_cmds.h" nogil:

    int sg_cmds_open_device(const char *, bint, int)
    int sg_cmds_close_device(int)
    int sg_ll_persistent_reserve_in(int, int, void *, int, bint, int)
    int sg_ll_persistent_reserve_out(int, int, int, unsigned int, void *, int, bint, int)
