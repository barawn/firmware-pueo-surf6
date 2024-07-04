# PUEO Signal and Event Buffer components

The PUEO signal buffer (SIGBUF) and event buffer (EVBUF)
components are here.

SIGBUF is a circular buffer which stores data from the RFSoC
directly with no modification (other than storing only the top
12 bits) with a programmable depth (currently nominally 32.768 us).
This is where data is recorded to accomodate a large trigger latency.
Data is read in and out at 500 MHz x 72 bits.

EVBUF is the event buffer, which stores data requested from
a trigger until fully transmitted. The event buffer can currently
store up to 8 events, and writes data at 500 MHz x 72 bits
(matching SIGBUF) and reads data out at 125 MHz x 8 bits x
(1 transfer / 2 cycles) = 500 Mbit/s, matching the output data
rate to the TURFIO.

There's a lot of weird machinations to balance the amount
of logic levels needed to operate at 500 MHz. Both SIGBUF
and EVBUF consist of fully-cascaded URAM and BRAM to limit
the amount of fabric connectivity needed. This may require
some amount of pipeline registers between pueo_uram_v3.sv
and uram_event_buffer.sv if the physical distance between
the source URAM and destination BRAM is too large.

There are also quite a lot of multicycle path situations
in these modules so constraints need to take this into
consideration. However, the limitations of the set_multicycle_path
constraint might mean that I just end up developing
custom attributes to automate this myself.

Documentation for these modules is ongoing.