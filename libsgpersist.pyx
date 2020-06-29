# cython: language_level=3, c_string_type=unicode, c_string_encoding=default

from pxd cimport sg_lib, sg_cmds, sg_unaligned
from libc.stdint cimport uint8_t, uint32_t, uint64_t
from libc.stdlib cimport free

import enum

MX_ALLOC_LEN = 8192


class PRInActions(enum.IntEnum):

    READ_KEYS = 0x0
    READ_RESERVATION = 0x1


class PROutActions(enum.IntEnum):

    REGISTER_KEY = 0x0
    RESERVE_KEY = 0x1
    CLEAR_KEY = 0x3
    PREEMPT_KEY = 0x4
    REGISTER_IGNORE_KEY = 0x6


cdef class SCSIDevice(object):

    # for sg_cmds_open_device
    cdef const char* device
    cdef bint readonly
    cdef int verbose
    cdef int fd

    # for sg_memalign
    cdef uint32_t num_bytes
    cdef uint32_t align_to
    cdef uint8_t* pr_buff
    cdef uint8_t* free_pr_buff
    cdef bint vb

    def __cinit__(self, device, readonly=True, verbose=0):

        # for sg_cmds.sg_cmds_open_device
        self.device = device
        self.readonly = readonly
        self.verbose = verbose

        # for sg_memalign
        self.num_bytes = MX_ALLOC_LEN
        self.align_to = 0
        self.pr_buff = NULL
        self.free_pr_buff = NULL
        self.vb = False

        with nogil:
            # open the device
            self.fd = sg_cmds.sg_cmds_open_device(
                self.device,
                self.readonly,
                self.verbose
            )
            if self.fd < 0:
                raise OSError(f'Failed to open: {self.device}')

            # allocate memory off heap
            self.pr_buff = sg_lib.sg_memalign(
                self.num_bytes,
                self.align_to,
                &self.free_pr_buff,
                self.vb,
            )
            if self.pr_buff == NULL:
                raise MemoryError()

    def __dealloc__(self):

        with nogil:
            if self.fd >= 0:
                sg_cmds.sg_cmds_close_device(self.fd)

            if self.free_pr_buff != NULL:
                free(self.free_pr_buff)

    def prin_work(self, op):

        cdef int action = op
        cdef int res
        cdef unsigned int pr_gen
        cdef int add_len
        cdef int num = 0
        cdef int entries = 0

        with nogil:
            res = sg_cmds.sg_ll_persistent_reserve_in(
                self.fd,
                action,
                self.pr_buff,
                self.num_bytes,
                self.vb,
                self.verbose,
            )

        if res == -1:
            if action == PRInActions.READ_KEYS.value:
                raise RuntimeError('Failed to read keys.')
            elif action == PRInActions.READ_RESERVATION.value:
                raise RuntimeError('Failed to read reservation.')
            else:
                # should never get here
                raise RuntimeError('Unknown error')
        elif res == 6:
            # UNIT ATTENTION SENSE
            # Doesn't necessarily mean keys were preempted, but 6 is
            # always the returned int when a preemption occurs so
            # treat it this way always
            raise RuntimeError('Registration Preempted')

        with nogil:
            pr_gen = sg_unaligned.sg_get_unaligned_be32(self.pr_buff + 0)
            add_len = sg_unaligned.sg_get_unaligned_be32(self.pr_buff + 4)

        if action == PRInActions.READ_KEYS.value:
            num = 8
        elif action == PRInActions.READ_RESERVATION.value:
            num = 16

        entries = add_len // num

        return {
            'generation': pr_gen,
            'entries': entries,
        }

    def read_keys(self):
        """
        Read the registered keys on the disk (if any).
        """

        cdef uint8_t* bp
        cdef uint64_t key

        data = self.prin_work(PRInActions.READ_KEYS.value)

        data['keys'] = []

        bp = self.pr_buff + 8
        for i in range(data['entries']):
            with nogil:
                key = sg_unaligned.sg_get_unaligned_be64(bp + 0)
            data['keys'].append(key)
            bp += 8

        return data

    def read_reservation(self):
        """
        Read the persistent reservation on the disk (if any).
        """

        cdef uint8_t* bp
        cdef uint64_t resv

        data = self.prin_work(PRInActions.READ_RESERVATION.value)

        if data['entries'] > 0:

            bp = self.pr_buff + 8
            with nogil:
                resv = sg_unaligned.sg_get_unaligned_be64(bp)

            data['reservation'] = resv
            data['scopetype'] = (bp[13] & 0xf)

            return data

    def prout_work(self, op, crkey=0, nrkey=0):

        cdef int length = 24
        cdef int res
        cdef int rq_scope = 0
        cdef bint noisy = False
        cdef uint32_t prout_type = 1 # write exclusive
        cdef uint64_t crk = crkey
        cdef uint64_t nrk = nrkey
        cdef int action = op

        with nogil:
            sg_unaligned.sg_put_unaligned_be64(crk, (self.pr_buff + 0))
            sg_unaligned.sg_put_unaligned_be64(nrk, (self.pr_buff + 8))

            res = sg_cmds.sg_ll_persistent_reserve_out(
                self.fd,
                action,
                rq_scope,
                prout_type,
                self.pr_buff,
                length,
                noisy,
                self.verbose,
            )

        if res == -1:
            if action == PROutActions.REGISTER_KEY.value:
                raise RuntimeError('Failed to register key.')
            if action == PROutActions.REGISTER_IGNORE_KEY.value:
                raise RuntimeError('Failed to register and ignore existing key.')
            if action == PROutActions.RESERVE_KEY.value:
                raise RuntimeError('Failed to place reservation.')
            if action == PROutActions.PREEMPT_KEY.value:
                raise RuntimeError('Failed to preempt key.')
        elif res == 6:
            # UNIT ATTENTION SENSE
            # Doesn't necessarily mean keys were preempted, but 6 is
            # always the returned int when a preemption occurs so
            # treat it this way always
            raise RuntimeError('Registration Preempted')

    def update_key(self, crkey, nrkey):
        """
        This function updates an existing key
        on the disk.
        """

        cdef uint64_t crk = crkey
        cdef uint64_t nrk = nrkey

        self.prout_work(
            PROutActions.REGISTER_KEY.value, crkey=crk, nrkey=nrk
        )

    def register_new_key(self, nrkey):
        """
        This function registers a new key to the disk.
        """

        cdef uint64_t nrk = nrkey

        self.prout_work(
            PROutActions.REGISTER_KEY.value, nrkey=nrk
        )

    def register_ignore_key(self, nrkey):
        """
        This function registers a key to a disk
        ignoring any keys that already exist that
        are owned by us (if any).
        """

        cdef uint64_t nrk = nrkey

        self.prout_work(
            PROutActions.REGISTER_IGNORE_KEY.value, nrkey=nrk
        )

    def reserve_key(self, crkey):
        """
        Reserves the disk (WR_EXCLUSIVE) using `crkey`.
        """

        cdef uint64_t crk = crkey

        self.prout_work(
            PROutActions.RESERVE_KEY.value, crkey=crk
        )

    def preempt_key(self, crkey, prkey):
        """
        Preempts an existing key (`crkey`) that is
        reserving the disk and places a new persistent
        reservation (`prkey`) on the disk.
        """

        cdef uint64_t crk = crkey
        cdef uint64_t nrk = prkey

        self.register_ignore_key(nrk)

        self.prout_work(
            PROutActions.PREEMPT_KEY.value, crkey=nrk, nrkey=crk
        )
