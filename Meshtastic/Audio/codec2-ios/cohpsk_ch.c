/*---------------------------------------------------------------------------*\

  FILE........: cohpsk_ch.c
  AUTHOR......: David Rowe
  DATE CREATED: May 2015

  Channel impairment program for testing command line versions of
  cohpsk modem.

  TODO:
    [ ] measure and prints pwrs to check, prints warning
    [ ] SNR in 3000Hz input
    [ ] example operation with sox for sample rate change
    [ ] way to calibrate for different input pwrs
    [ ] HT to do real->complex
        [ ] check no BER hit just through HT
        [ ] unit test HT
    [ ] clipping detect

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2015 David Rowe

  All rights reserved.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License version 2, as
  published by the Free Software Foundation.  This program is
  distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program; if not, see <http://www.gnu.org/licenses/>.
*/

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

#include "codec2_cohpsk.h"
#include "comp_prim.h"
#include "noise_samples.h"
#include "ht_coeff.h"
#include "ssbfilt_coeff.h"
#include "codec2_fdmdv.h"

#define BUF_N                 160
#define FAST_FADING_DELAY_MS  2.0
#define SLOW_FADING_DELAY_MS  0.5
#define PAPR_TARGET           7.0

/* This file gets generated using the function write_noise_file in tcohpsk.m.  You have to run
   tcohpsk first (any variant) to load the function into Octave, e.g.:

  octave:17> tcohpsk
  octave:18> write_noise_file("../raw/fading_samples.float", 7500, 7500*60)
*/

#define FAST_FADING_FILE_NAME "../../raw/fast_fading_samples.float"
#define SLOW_FADING_FILE_NAME "../../raw/slow_fading_samples.float"

int main(int argc, char *argv[])
{
    FILE          *fin, *ffading, *fout;
    float          NodB, foff_hz;
    int            fading_en, nhfdelay;

    short          buf[BUF_N];
    float          htbuf[HT_N+BUF_N];
    COMP           ch_in[BUF_N];
    COMP           ch_fdm[BUF_N];
    float          ssbfiltbuf[SSBFILT_N+BUF_N];
    float          ssbfiltout[BUF_N];

    COMP           phase_ch;
    int            noise_r, noise_end;
    float          No, variance;
    COMP           scaled_noise;
    float          hf_gain;
    COMP          *ch_fdm_delay, aspread, aspread_2ms, delayed, direct;
    float          tx_pwr, tx_pwr_fade, noise_pwr;
    int            frames, i, j, k, ret, clipped;
    float          sam, peak, inclip, papr, CNo, snr3k, EbNo700;

    if (argc == 7) {
        if (strcmp(argv[1], "-")  == 0) fin = stdin;
        else if ( (fin = fopen(argv[1],"rb")) == NULL ) {
            fprintf(stderr, "Error opening input modem raw file: %s: %s.\n",
                    argv[1], strerror(errno));
            exit(1);
        }

        if (strcmp(argv[2], "-") == 0) fout = stdout;
        else if ( (fout = fopen(argv[2],"wb")) == NULL ) {
            fprintf(stderr, "Error opening output modem raw file: %s: %s.\n",
                    argv[2], strerror(errno));
            exit(1);
        }

        NodB = atof(argv[3]);
        foff_hz = atof(argv[4]);
        fading_en = atoi(argv[5]);
        inclip = atof(argv[6]);
    }
    else {
        fprintf(stderr, "usage: %s InputRealModemRawFileFs7500Hz OutputRealModemRawFileFs7500Hz No(dB/Hz) FoffHz Fading[0-none 1-fast 2-slow] InputClip0to1\n", argv[0]);
        exit(1);
    }
    fprintf(stderr, "NodB: %4.2f foff: %4.2f Hz fading: %d inclip: %4.2f\n", NodB, foff_hz, fading_en, inclip);

    phase_ch.real = 1.0; phase_ch.imag = 0.0;
    noise_r = 0;
    noise_end = sizeof(noise)/sizeof(COMP);

    /*  N = var = NoFs */

    No = pow(10.0, NodB/10.0);
    variance = COHPSK_FS*No;

    tx_pwr = tx_pwr_fade = noise_pwr = 0.0;
    clipped = 0;
    peak = 0.0;

    /* init HF fading model */

    if (fading_en) {
        if (fading_en == 1) {
            ffading = fopen(FAST_FADING_FILE_NAME, "rb");
            if (ffading == NULL) {
                printf("Can't find fast fading file: %s\n", FAST_FADING_FILE_NAME);
                exit(1);
            }
            nhfdelay = floor(FAST_FADING_DELAY_MS*COHPSK_FS/1000);
        }

        if (fading_en == 2) {
            ffading = fopen(SLOW_FADING_FILE_NAME, "rb");
            if (ffading == NULL) {
                printf("Can't find slow fading file: %s\n", SLOW_FADING_FILE_NAME);
                exit(1);
            }
            nhfdelay = floor(SLOW_FADING_DELAY_MS*COHPSK_FS/1000);
        }

        ch_fdm_delay = (COMP*)malloc((nhfdelay+COHPSK_NOM_SAMPLES_PER_FRAME)*sizeof(COMP));
        assert(ch_fdm_delay != NULL);
        for(i=0; i<nhfdelay+COHPSK_NOM_SAMPLES_PER_FRAME; i++) {
            ch_fdm_delay[i].real = 0.0;
            ch_fdm_delay[i].imag = 0.0;
        }

        /* first values in file are HF gains */

        for (i=0; i<4; i++)
            ret = fread(&hf_gain, sizeof(float), 1, ffading);
        fprintf(stderr, "hf_gain: %f\n", hf_gain);
    }

    for(i=0; i<HT_N; i++) {
        htbuf[i] = 0.0;
    }

    /* --------------------------------------------------------*\
	                          Main Loop
    \*---------------------------------------------------------*/

    while(fread(buf, sizeof(short), BUF_N, fin) == BUF_N) {
	frames++;

        /* Hilbert Transform to produce complex signal so we can do
           single sided freq shifts.  Allows us to use real signal I/O
           which is handy */

        for(i=0, j=HT_N; i<BUF_N; i++,j++) {

            /*
               Hilbert Transform to produce complex signal so we can do
               single sided freq shifts.  Essential filters out negative
               freqencies.
            */

            sam = (float)buf[i];
            //printf("sam: %f ", sam);
            if (sam > inclip*32767.0)
                sam = inclip*32767.0;
            if (sam < -inclip*32767.0)
                sam = -inclip*32767.0;
            //printf("sam: %f\n", sam);
            htbuf[j] = sam/FDMDV_SCALE;

            if (fabs(htbuf[j]) > peak) {
                peak = fabs(htbuf[j]);
            }
            tx_pwr += pow(htbuf[j], 2.0);

            /* FIR filter with HT to get imag, just delay to get real */

            ch_in[i].real = 0.0;
            ch_in[i].imag = 0.0;
            for(k=0; k<HT_N; k++) {
                ch_in[i].real += htbuf[j-k]*ht_coeff[k].real;
                ch_in[i].imag += htbuf[j-k]*ht_coeff[k].imag;
            }
            //printf("%d %f %f\n", i, ch_in[i].real, ch_in[i].imag);
        }
        assert(j <= (BUF_N+HT_N));

        /* update HT memory */

        for(i=0; i<HT_N; i++)
           htbuf[i] = htbuf[i+BUF_N];

	/* --------------------------------------------------------*\
	                          Channel
	\*---------------------------------------------------------*/

        fdmdv_freq_shift(ch_fdm, ch_in, foff_hz, &phase_ch, BUF_N);

        /* optional HF fading -------------------------------------*/

        if (fading_en) {

            /* update delayed signal buffer */

            for(i=0; i<nhfdelay; i++)
                ch_fdm_delay[i] = ch_fdm_delay[i+BUF_N];
            for(j=0; j<BUF_N; i++, j++)
                ch_fdm_delay[i] = ch_fdm[j];

            /* combine direct and delayed paths, both multiplied by
               "spreading" (doppler) functions */

            for(i=0; i<BUF_N; i++) {
                ret = fread(&aspread, sizeof(COMP), 1, ffading);
                assert(ret == 1);
                ret = fread(&aspread_2ms, sizeof(COMP), 1, ffading);
                assert(ret == 1);
                //printf("%f %f %f %f\n", aspread.real, aspread.imag, aspread_2ms.real, aspread_2ms.imag);

                direct    = cmult(aspread, ch_fdm[i]);
                delayed   = cmult(aspread_2ms, ch_fdm_delay[i]);
                ch_fdm[i] = fcmult(hf_gain, cadd(direct, delayed));
            }
        }

        /* Measure power after fading model to make sure aaverage pwr
           is the same as AWGN channels. We only output the real
           signal, which is half the power. */

        for(i=0; i<BUF_N; i++) {
            tx_pwr_fade += pow(ch_fdm[i].real, 2.0);
        }

        /* AWGN noise ------------------------------------------*/

        for(i=0; i<BUF_N; i++) {
            scaled_noise = fcmult(sqrt(variance), noise[noise_r]);
            ch_fdm[i] = cadd(ch_fdm[i], scaled_noise);
            noise_pwr += pow(scaled_noise.real, 2.0);
            noise_r++;
            if (noise_r > noise_end) {
                noise_r = 0;
                //fprintf(stderr, "  [%d] noise wrap\n", f);
            }
        }

        /* FIR filter to simulate (a rather flat) SSB filter.  Might
           be useful to have an option for a filter with a few dB
           ripple too, to screw up the modem. This is mainly so analog
           SSB sounds realistic. */

        for(i=0, j=SSBFILT_N; i<BUF_N; i++,j++) {
            ssbfiltbuf[j] = ch_fdm[i].real;
            ssbfiltout[i] = 0.0;
            for(k=0; k<SSBFILT_N; k++) {
                ssbfiltout[i] += ssbfiltbuf[j-k]*ssbfilt_coeff[k];
            }
        }

        /* update SSB filter memory */

        for(i=0; i<SSBFILT_N; i++)
           ssbfiltbuf[i] = ssbfiltbuf[i+BUF_N];

	/* scale and save to disk as shorts */

	for(i=0; i<BUF_N; i++) {
            sam = FDMDV_SCALE * ssbfiltout[i];
            if (sam > 32767.0) {
                clipped++;
                sam = 32767.0;
            }
            if (sam < -32767.0) {
                clipped++;
                sam = -32767.0;
            }
	    buf[i] = sam;
        }

 	fwrite(buf, sizeof(short), BUF_N, fout);

	/* if this is in a pipeline, we probably don't want the usual
	   buffering to occur */

        if (fout == stdout) fflush(stdout);
        if (fin == stdin) fflush(stdin);
    }

    fclose(fin);
    fclose(fout);

    fprintf(stderr, "peak pwr.....: %7.2f\nav input pwr.: %7.2f\nav pwr fading: %7.2f\nnoise pwr....: %7.2f\nclipping.....: %7.2f %%\n",
            peak*peak,
            tx_pwr/(frames*BUF_N),
            tx_pwr_fade/(frames*BUF_N),
            noise_pwr/(frames*BUF_N),
            100.0*clipped/frames
           );
    papr = 10*log10(peak*peak/(tx_pwr/(frames*BUF_N)));
    CNo = 10*log10(tx_pwr/(noise_pwr/(COHPSK_FS/2))); // single sided spctrum magic IDFK!
    snr3k = CNo - 10*log10(3000);
    EbNo700 = CNo - 10*log10(700) - 10*log10(6.0/4.0); // divide by bit rate and pilot overhead
    fprintf(stderr, "PAPR (dB)....: %7.2f (target %3.2f)\nC/No (dB)....: %7.2f\nSNR3k........: %7.2f\nEb/No(Rb=700): %7.2f\n",
            papr,
            PAPR_TARGET,
            CNo,
            snr3k,
            EbNo700
            );

    return 0;
}

