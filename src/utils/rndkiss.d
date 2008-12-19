//Code adapted from tango.math.Random (www.dsource.org/projects/tango, BSD)
module utils.rndkiss;

import utils.time;
import utils.misc;

/******************************************************************************

        KISS (via George Marsaglia & Paul Hsieh)

        the idea is to use simple, fast, individually promising
        generators to get a composite that will be fast, easy to code
        have a very long period and pass all the tests put to it.
        The three components of KISS are

                x(n)=a*x(n-1)+1 mod 2^32
                y(n)=y(n-1)(I+L^13)(I+R^17)(I+L^5),
                z(n)=2*z(n-1)+z(n-2) +carry mod 2^32

        The y's are a shift register sequence on 32bit binary vectors
        period 2^32-1; The z's are a simple multiply-with-carry sequence
        with period 2^63+2^32-1.

        The period of KISS is thus 2^32*(2^32-1)*(2^63+2^32-1) > 2^127

******************************************************************************/

struct RNGState {
    uint kiss_k;
    uint kiss_m;
    uint kiss_x = 1;
    uint kiss_y = 2;
    uint kiss_z = 4;
    uint kiss_w = 8;
    uint kiss_carry = 0;
}

class Random
{
    private RNGState kissSt;

    /**********************************************************************
        Creates and seeds a new generator with the current time
    **********************************************************************/
    this ()
    {
        this.seed;
    }

    /**********************************************************************
        Seed the generator with current time
    **********************************************************************/
    final void seed()
    {
        seed(cast(uint) timeCurrentTime().musecs);
    }

    /**********************************************************************
        Seed the generator with a provided value
    **********************************************************************/
    final void seed(uint seed)
    {
            kissSt.kiss_x = seed | 1;
            kissSt.kiss_y = seed | 2;
            kissSt.kiss_z = seed | 4;
            kissSt.kiss_w = seed | 8;
            kissSt.kiss_carry = 0;
    }

    /**********************************************************************
        Returns X such that 0 <= X <= uint.max
    **********************************************************************/
    final uint next()
    {
        kissSt.kiss_x = kissSt.kiss_x * 69069 + 1;
        kissSt.kiss_y ^= kissSt.kiss_y << 13;
        kissSt.kiss_y ^= kissSt.kiss_y >> 17;
        kissSt.kiss_y ^= kissSt.kiss_y << 5;
        kissSt.kiss_k = (kissSt.kiss_z >> 2) + (kissSt.kiss_w >> 3)
            + (kissSt.kiss_carry >> 2);
        kissSt.kiss_m = kissSt.kiss_w + kissSt.kiss_w + kissSt.kiss_z
            + kissSt.kiss_carry;
        kissSt.kiss_z = kissSt.kiss_w;
        kissSt.kiss_w = kissSt.kiss_m;
        kissSt.kiss_carry = kissSt.kiss_k >> 30;
        return kissSt.kiss_x + kissSt.kiss_y + kissSt.kiss_w;
    }

    /**********************************************************************
        Returns X such that 0 <= X < max

        Note that max is exclusive, making it compatible with
        array indexing
    **********************************************************************/
    final uint next(uint max)
    {
        return next() % max;
    }

    /**********************************************************************
        Returns X such that min <= X < max

        Note that max is exclusive, making it compatible with
        array indexing
    **********************************************************************/
    final int next(int min, int max)
    {
        assert(min != max);
        if (max < min)
            swap(max, min);
        return next(max-min) + min;
    }

    //[0.0f, 1.0f]
    final double nextDouble()
    {
        return next()*(1.0/4294967295.0);
        /* divided by 2^32-1 */
    }

    //[0.0f, 1.0f)
    final double nextDouble2()
    {
        return next()*(1.0/4294967296.0);
        /* divided by 2^32 */
    }

    //[-1.0f..1.0f]
    final double nextDouble3() {
        return (nextDouble()-0.5)*2.0;
    }

    /// min <= X <= max (integer types only)
    T nextRange(T)(T min, T max) {
        return cast(T)(min + (max-min+1)*nextDouble2());
    }

    /**
     save/restore internal state, for setting the generator
     back to a specific point in the sequence
    */
    final RNGState state() {
        return kissSt;
    }
    final void state(RNGState newState) {
        kissSt = newState;
    }
}

