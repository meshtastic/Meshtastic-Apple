/*---------------------------------------------------------------------------*\

  FILE........: cohpsk_demod.c
  AUTHOR......: David Rowe
  DATE CREATED: April 6 2015

  Given an input file of raw file (8kHz, 16 bit shorts) of COHPSK modem samples,
  outputs a file of bits (note one bit per int, not compressed).

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
#include "cohpsk_defs.h"
#include "cohpsk_internal.h"
#include "codec2_fdmdv.h"
#include "octave.h"

#define LOG_FRAMES 100
#define SYNC_FRAMES 12                    /* sync state uses up extra log storage as we reprocess several times */

int main(int argc, char *argv[])
{
    FILE          *fin, *fout, *foct;
    struct COHPSK *cohpsk;
    float         rx_bits[COHPSK_BITS_PER_FRAME];
    char          rx_bits_char[COHPSK_BITS_PER_FRAME];
    COMP          rx_fdm[COHPSK_MAX_SAMPLES_PER_FRAME];
    short         rx_fdm_scaled[COHPSK_MAX_SAMPLES_PER_FRAME];
    int           frames, sync, nin_frame;
    float        *rx_amp_log;
    float        *rx_phi_log;
    COMP         *rx_symb_log;
    float         f_est_log[LOG_FRAMES], ratio_log[LOG_FRAMES];
    int           i, r, c, log_data_r, oct, logframes;

    if (argc < 3) {
	printf("usage: %s InputModemRawFile OutputOneBitPerIntFile [OctaveLogFile]\n", argv[0]);
	exit(1);
    }

    if (strcmp(argv[1], "-")  == 0) fin = stdin;
    else if ( (fin = fopen(argv[1],"rb")) == NULL ) {
	fprintf(stderr, "Error opening input modem sample file: %s: %s.\n",
         argv[1], strerror(errno));
	exit(1);
    }

    if (strcmp(argv[2], "-") == 0) fout = stdout;
    else if ( (fout = fopen(argv[2],"wb")) == NULL ) {
	fprintf(stderr, "Error opening output file: %s: %s.\n",
         argv[2], strerror(errno));
	exit(1);
    }

    foct = NULL;
    oct = 0;
    if (argc == 4) {
        if ( (foct = fopen(argv[3],"wt")) == NULL ) {
            fprintf(stderr, "Error opening output Octave file: %s: %s.\n",
                    argv[3], strerror(errno));
	exit(1);
        }
        oct = 1;
    }

    cohpsk = cohpsk_create();
    cohpsk_set_verbose(cohpsk, 1);

    if (oct) {
        logframes = LOG_FRAMES;
        rx_amp_log = (float *)malloc(sizeof(float)*logframes*NSYMROW*COHPSK_NC*ND);
        assert(rx_amp_log != NULL);
        rx_phi_log = (float *)malloc(sizeof(float)*logframes*NSYMROW*COHPSK_NC*ND);
        assert(rx_phi_log != NULL);
        rx_symb_log = (COMP *)malloc(sizeof(COMP)*logframes*NSYMROW*COHPSK_NC*ND);
        assert(rx_symb_log != NULL);
        cohpsk->rx_timing_log = (float*)malloc(sizeof(float)*SYNC_FRAMES*logframes*NSYMROWPILOT);
        assert(cohpsk->rx_timing_log != NULL);
    }

    log_data_r = 0;
    frames = 0;

    nin_frame = COHPSK_NOM_SAMPLES_PER_FRAME;
    while(fread(rx_fdm_scaled, sizeof(short), nin_frame, fin) == nin_frame) {
	frames++;
        cohpsk_set_frame(cohpsk, frames);

	/* scale and demod */

	for(i=0; i<nin_frame; i++) {
	    rx_fdm[i].real = rx_fdm_scaled[i]/FDMDV_SCALE;
            rx_fdm[i].imag = 0.0;
        }

	cohpsk_demod(cohpsk, rx_bits, &sync, rx_fdm, &nin_frame);

 	if (sync) {
            for(i=0; i<COHPSK_BITS_PER_FRAME; i++)
                rx_bits_char[i] = rx_bits[i] < 0.0;
            fwrite(rx_bits_char, sizeof(char), COHPSK_BITS_PER_FRAME, fout);

            if (oct) {
                for(r=0; r<NSYMROW; r++, log_data_r++) {
                    for(c=0; c<COHPSK_NC*ND; c++) {
                        rx_amp_log[log_data_r*COHPSK_NC*ND+c] = cohpsk->amp_[r][c];
                        rx_phi_log[log_data_r*COHPSK_NC*ND+c] = cohpsk->phi_[r][c];
                        rx_symb_log[log_data_r*COHPSK_NC*ND+c] = cohpsk->rx_symb[r][c];
                    }
                }

                f_est_log[frames-1] = cohpsk->f_est;
                ratio_log[frames-1] = cohpsk->ratio;
                //fprintf(stderr,"ratio: %f\n", cohpsk->ratio);

                //printf("frames: %d log_data_r: %d\n", frames, log_data_r);
                if (frames == logframes)
                    oct = 0;
            }
        }

	/* if this is in a pipeline, we probably don't want the usual
	   buffering to occur */

        if (fout == stdout) fflush(stdout);
        if (fin == stdin) fflush(stdin);
    }

    fclose(fin);
    fclose(fout);

    /* optionally dump Octave files */

    if (foct != NULL) {
        octave_save_float(foct, "rx_amp_log_c", (float*)rx_amp_log, log_data_r, COHPSK_NC*ND, COHPSK_NC*ND);
        octave_save_float(foct, "rx_phi_log_c", (float*)rx_phi_log, log_data_r, COHPSK_NC*ND, COHPSK_NC*ND);
        octave_save_complex(foct, "rx_symb_log_c", (COMP*)rx_symb_log, log_data_r, COHPSK_NC*ND, COHPSK_NC*ND);
        octave_save_float(foct, "rx_timing_log_c", (float*)cohpsk->rx_timing_log, 1, cohpsk->rx_timing_log_index, cohpsk->rx_timing_log_index);
        octave_save_float(foct, "f_est_log_c", f_est_log, 1, logframes, logframes);
        octave_save_float(foct, "ratio_log_c", ratio_log, 1, logframes, logframes);
        fclose(foct);
    }

    cohpsk_destroy(cohpsk);


    return 0;
}
