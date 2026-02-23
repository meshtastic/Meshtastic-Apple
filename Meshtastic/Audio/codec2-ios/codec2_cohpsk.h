/*---------------------------------------------------------------------------*\

  FILE........: codec2_cohpsk.h
  AUTHOR......: David Rowe
  DATE CREATED: March 2015

  Functions that implement a coherent PSK FDM modem.

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2015 David Rowe

  All rights reserved.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License version 2.1, as
  published by the Free Software Foundation.  This program is
  distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program; if not, see <http://www.gnu.org/licenses/>.
*/

#ifndef __CODEC2_COHPSK__
#define __CODEC2_COHPSK__

#define COHPSK_BITS_PER_FRAME         56              /* hard coded for now */
#define COHPSK_NC                      7              /* hard coded for now */
#define COHPSK_NOM_SAMPLES_PER_FRAME 600
#define COHPSK_MAX_SAMPLES_PER_FRAME 625
#define COHPSK_RS                     75
#define COHPSK_FS                   7500              /* note this is a wierd
                                                         value to get an integer
                                                         oversampling rate */

#include "comp.h"
#include "modem_stats.h"

struct COHPSK;

extern const int test_bits_coh[];

struct COHPSK *cohpsk_create(void);
void cohpsk_destroy(struct COHPSK *coh);
void cohpsk_mod(struct COHPSK *cohpsk, COMP tx_fdm[], int tx_bits[]);
void cohpsk_clip(COMP tx_fdm[]);
void cohpsk_demod(struct COHPSK *cohpsk, float rx_bits[], int *sync, COMP rx_fdm[], int *nin_frame);
void cohpsk_get_demod_stats(struct COHPSK *cohpsk, struct MODEM_STATS *stats);
void cohpsk_set_verbose(struct COHPSK *coh, int verbose);
void cohpsk_get_test_bits(struct COHPSK *coh, int rx_bits[]);
void cohpsk_put_test_bits(struct COHPSK *coh, int *state, short error_pattern[],
                          int *bit_errors, char rx_bits_sd[]);
int cohpsk_error_pattern_size(void);
void cohpsk_set_frame(struct COHPSK *coh, int frame);
void fdmdv_freq_shift_coh(COMP rx_fdm_fcorr[], COMP rx_fdm[], float foff, float Fs,
                          COMP *foff_phase_rect, int nin);
#endif
