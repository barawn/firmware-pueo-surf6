# Programmable biquad filter for PUEO

## Background

Any IIR filter can be split up into cascaded sections of
second-order filters (a 'biquad', or second order section [sos]),
plus a possible first-order final stage if the filter order is odd
(we do not care about this possibility).

This module therefore implements a single programmable biquad IIR
running at 8x super sample rate (SSR), meaning 8 samples per clock.
In literature terminology this is often called a "parallel" or "block"
filter. The filter is additionally pipelined in order to reach
the necessary clock speeds. This is therefore a parallel, pipelined,
super sample rate biquad, using incremental processing for the
parallelization.

See Parhi "VLSI Digital Signal Processing Systems" for a good introduction.

For most cases, second-order filters consist of conjugate poles, and
this implementation focuses on that. If the second order section
consists of 2 _real_ poles, this implementation may not work. At least
the math supporting the coefficient calculation does not.

## Coefficient calcs

https://github.com/barawn/pueo-dsp-python/tree/main/dsp

## Sections

Converting an IIR to a M-block/parallel structure essentially consists of

1. split off the numerator (FIR) portion
2. rewrite the difference equation for the IIR portion such that for 2 of
   the terms, they are only in terms of known coefficients from previous clocks.
   This calculation in the end consists of 2 coupled IIRs and 2 additional FIRs.
   In terms of what is happening to the polynomial, we are adding
   cancelling pole/zero pairs to rewrite the denominator in terms of
   z^-M and z^-(M-1) coefficients only.
3. use an incremental processing approach to calculate the remaining (M-2)
   outputs afterwards.

We _do not handle_ the first (FIR) portion here yet. For standard notch
filters this portion should be simple since it is fundamentally
y=K(x - axz^-1 + xz^-2) which can be handled in a single DSP per sample.

The 2nd portion is in biquad8_pole_fir (the FIR portion) and biquad8_pole_iir
(the IIR portion), and the 3rd portion is in biquad8_incremental.

An example of putting them all together is at:

https://github.com/barawn/pueo_tv/blob/main/hdl/pueo_tv.v