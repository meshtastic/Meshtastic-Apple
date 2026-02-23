/*---------------------------------------------------------------------------*\

  FILE........: codec2.c
  AUTHOR......: David Rowe
  DATE CREATED: 21/8/2010

  Codec2 fully quantised encoder and decoder functions.  If you want use
  codec2, the codec2_xxx functions are for you.

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2010 David Rowe

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

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "defines.h"
#include "sine.h"
#include "nlp.h"
#include "dump.h"
#include "lpc.h"
#include "quantise.h"
#include "phase.h"
#include "interp.h"
#include "postfilter.h"
#include "codec2.h"
#include "lsp.h"
#include "codec2_internal.h"
#include "machdep.h"
#include "bpf.h"
#include "bpfb.h"

/*---------------------------------------------------------------------------*\

                             FUNCTION HEADERS

\*---------------------------------------------------------------------------*/

void analyse_one_frame(struct CODEC2 *c2, MODEL *model, short speech[]);
void synthesise_one_frame(struct CODEC2 *c2, short speech[], MODEL *model,
			  COMP Aw[]);
void codec2_encode_3200(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_3200(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_2400(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_2400(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_1600(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_1600(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_1400(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_1400(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_1300(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_1300(struct CODEC2 *c2, short speech[], const unsigned char * bits, float ber_est);
void codec2_encode_1200(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_1200(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_700(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_700(struct CODEC2 *c2, short speech[], const unsigned char * bits);
void codec2_encode_700b(struct CODEC2 *c2, unsigned char * bits, short speech[]);
void codec2_decode_700b(struct CODEC2 *c2, short speech[], const unsigned char * bits);
static void ear_protection(float in_out[], int n);

/*---------------------------------------------------------------------------*\

                                FUNCTIONS

\*---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_create
  AUTHOR......: David Rowe
  DATE CREATED: 21/8/2010

  Create and initialise an instance of the codec.  Returns a pointer
  to the codec states or NULL on failure.  One set of states is
  sufficient for a full duuplex codec (i.e. an encoder and decoder).
  You don't need separate states for encoders and decoders.  See
  c2enc.c and c2dec.c for examples.

\*---------------------------------------------------------------------------*/

struct CODEC2 * codec2_create(int mode)
{
    struct CODEC2 *c2;
    int            i,l;

    if ((mode != CODEC2_MODE_3200) &&
	   (mode != CODEC2_MODE_2400) &&
	   (mode != CODEC2_MODE_1600) &&
	   (mode != CODEC2_MODE_1400) &&
	   (mode != CODEC2_MODE_1300) &&
	   (mode != CODEC2_MODE_1200) &&
	   (mode != CODEC2_MODE_700) &&
	   (mode != CODEC2_MODE_700B)
        ) {
        return NULL;
    }

    c2 = (struct CODEC2*)malloc(sizeof(struct CODEC2));
    if (c2 == NULL)
	return NULL;

    c2->mode = mode;
    for(i=0; i<M; i++)
	c2->Sn[i] = 1.0;
    c2->hpf_states[0] = c2->hpf_states[1] = 0.0;
    for(i=0; i<2*N; i++)
	c2->Sn_[i] = 0;
    c2->fft_fwd_cfg = kiss_fft_alloc(FFT_ENC, 0, NULL, NULL);
    make_analysis_window(c2->fft_fwd_cfg, c2->w,c2->W);
    make_synthesis_window(c2->Pn);
    c2->fft_inv_cfg = kiss_fft_alloc(FFT_DEC, 1, NULL, NULL);
    quantise_init();
    c2->prev_Wo_enc = 0.0;
    c2->bg_est = 0.0;
    c2->ex_phase = 0.0;

    for(l=1; l<=MAX_AMP; l++)
	c2->prev_model_dec.A[l] = 0.0;
    c2->prev_model_dec.Wo = TWO_PI/P_MAX;
    c2->prev_model_dec.L = PI/c2->prev_model_dec.Wo;
    c2->prev_model_dec.voiced = 0;

    for(i=0; i<LPC_ORD; i++) {
      c2->prev_lsps_dec[i] = i*PI/(LPC_ORD+1);
    }
    c2->prev_e_dec = 1;

    c2->nlp = nlp_create(M);
    if (c2->nlp == NULL) {
	free (c2);
	return NULL;
    }

    if (mode == CODEC2_MODE_700B)
        c2->gray = 0;             // natural binary better for trellis decoding (hopefully added later)
    else
        c2->gray = 1;

    c2->lpc_pf = 1; c2->bass_boost = 1; c2->beta = LPCPF_BETA; c2->gamma = LPCPF_GAMMA;

    c2->xq_enc[0] = c2->xq_enc[1] = 0.0;
    c2->xq_dec[0] = c2->xq_dec[1] = 0.0;

    c2->smoothing = 0;

    c2->bpf_buf = (float*)malloc(sizeof(float)*(BPF_N+4*N));
    assert(c2->bpf_buf != NULL);
    for(i=0; i<BPF_N+4*N; i++)
        c2->bpf_buf[i] = 0.0;

    c2->softdec = NULL;

    return c2;
}

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_destroy
  AUTHOR......: David Rowe
  DATE CREATED: 21/8/2010

  Destroy an instance of the codec.

\*---------------------------------------------------------------------------*/

void codec2_destroy(struct CODEC2 *c2)
{
    assert(c2 != NULL);
    free(c2->bpf_buf);
    nlp_destroy(c2->nlp);
    KISS_FFT_FREE(c2->fft_fwd_cfg);
    KISS_FFT_FREE(c2->fft_inv_cfg);
    free(c2);
}

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_bits_per_frame
  AUTHOR......: David Rowe
  DATE CREATED: Nov 14 2011

  Returns the number of bits per frame.

\*---------------------------------------------------------------------------*/

int codec2_bits_per_frame(struct CODEC2 *c2) {
    if (c2->mode == CODEC2_MODE_3200)
	return 64;
    if (c2->mode == CODEC2_MODE_2400)
	return 48;
    if  (c2->mode == CODEC2_MODE_1600)
	return 64;
    if  (c2->mode == CODEC2_MODE_1400)
	return 56;
    if  (c2->mode == CODEC2_MODE_1300)
	return 52;
    if  (c2->mode == CODEC2_MODE_1200)
	return 48;
    if  (c2->mode == CODEC2_MODE_700)
	return 28;
    if  (c2->mode == CODEC2_MODE_700B)
	return 28;

    return 0; /* shouldn't get here */
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_samples_per_frame
  AUTHOR......: David Rowe
  DATE CREATED: Nov 14 2011

  Returns the number of speech samples per frame.

\*---------------------------------------------------------------------------*/

int codec2_samples_per_frame(struct CODEC2 *c2) {
    if (c2->mode == CODEC2_MODE_3200)
	return 160;
    if (c2->mode == CODEC2_MODE_2400)
	return 160;
    if  (c2->mode == CODEC2_MODE_1600)
	return 320;
    if  (c2->mode == CODEC2_MODE_1400)
	return 320;
    if  (c2->mode == CODEC2_MODE_1300)
	return 320;
    if  (c2->mode == CODEC2_MODE_1200)
	return 320;
    if  (c2->mode == CODEC2_MODE_700)
	return 320;
    if  (c2->mode == CODEC2_MODE_700B)
	return 320;

    return 0; /* shouldnt get here */
}

void codec2_encode(struct CODEC2 *c2, unsigned char *bits, short speech[])
{
    assert(c2 != NULL);
    assert(
	   (c2->mode == CODEC2_MODE_3200) ||
	   (c2->mode == CODEC2_MODE_2400) ||
	   (c2->mode == CODEC2_MODE_1600) ||
	   (c2->mode == CODEC2_MODE_1400) ||
	   (c2->mode == CODEC2_MODE_1300) ||
	   (c2->mode == CODEC2_MODE_1200) ||
	   (c2->mode == CODEC2_MODE_700)  ||
	   (c2->mode == CODEC2_MODE_700B)
	   );

    if (c2->mode == CODEC2_MODE_3200)
	codec2_encode_3200(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_2400)
	codec2_encode_2400(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_1600)
	codec2_encode_1600(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_1400)
	codec2_encode_1400(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_1300)
	codec2_encode_1300(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_1200)
	codec2_encode_1200(c2, bits, speech);
#ifndef CORTEX_M4
    if (c2->mode == CODEC2_MODE_700)
	codec2_encode_700(c2, bits, speech);
    if (c2->mode == CODEC2_MODE_700B)
	codec2_encode_700b(c2, bits, speech);
#endif
}

void codec2_decode(struct CODEC2 *c2, short speech[], const unsigned char *bits)
{
    codec2_decode_ber(c2, speech, bits, 0.0);
}

void codec2_decode_ber(struct CODEC2 *c2, short speech[], const unsigned char *bits, float ber_est)
{
    assert(c2 != NULL);
    assert(
	   (c2->mode == CODEC2_MODE_3200) ||
	   (c2->mode == CODEC2_MODE_2400) ||
	   (c2->mode == CODEC2_MODE_1600) ||
	   (c2->mode == CODEC2_MODE_1400) ||
	   (c2->mode == CODEC2_MODE_1300) ||
	   (c2->mode == CODEC2_MODE_1200) ||
	   (c2->mode == CODEC2_MODE_700) ||
	   (c2->mode == CODEC2_MODE_700B)
	   );

    if (c2->mode == CODEC2_MODE_3200)
	codec2_decode_3200(c2, speech, bits);
    if (c2->mode == CODEC2_MODE_2400)
	codec2_decode_2400(c2, speech, bits);
    if (c2->mode == CODEC2_MODE_1600)
 	codec2_decode_1600(c2, speech, bits);
    if (c2->mode == CODEC2_MODE_1400)
 	codec2_decode_1400(c2, speech, bits);
    if (c2->mode == CODEC2_MODE_1300)
 	codec2_decode_1300(c2, speech, bits, ber_est);
    if (c2->mode == CODEC2_MODE_1200)
 	codec2_decode_1200(c2, speech, bits);
#ifndef CORTEX_M4
    if (c2->mode == CODEC2_MODE_700)
 	codec2_decode_700(c2, speech, bits);
    if (c2->mode == CODEC2_MODE_700B)
 	codec2_decode_700b(c2, speech, bits);
#endif
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_3200
  AUTHOR......: David Rowe
  DATE CREATED: 13 Sep 2012

  Encodes 160 speech samples (20ms of speech) into 64 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm twice.  On the
  first frame we just send the voicing bits.  On the second frame we
  send all model parameters.  Compared to 2400 we use a larger number
  of bits for the LSPs and non-VQ pitch and energy.

  The bit allocation is:

    Parameter                      bits/frame
    --------------------------------------
    Harmonic magnitudes (LSPs)     50
    Pitch (Wo)                      7
    Energy                          5
    Voicing (10ms update)           2
    TOTAL                          64

\*---------------------------------------------------------------------------*/

void codec2_encode_3200(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   ak[LPC_ORD+1];
    float   lsps[LPC_ORD];
    float   e;
    int     Wo_index, e_index;
    int     lspd_indexes[LPC_ORD];
    int     i;
    unsigned int nbit = 0;

    assert(c2 != NULL);

    memset(bits, '\0', ((codec2_bits_per_frame(c2) + 7) / 8));

    /* first 10ms analysis frame - we just want voicing */

    analyse_one_frame(c2, &model, speech);
    pack(bits, &nbit, model.voiced, 1);

    /* second 10ms analysis frame */

    analyse_one_frame(c2, &model, &speech[N]);
    pack(bits, &nbit, model.voiced, 1);
    Wo_index = encode_Wo(model.Wo, WO_BITS);
    pack(bits, &nbit, Wo_index, WO_BITS);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    e_index = encode_energy(e, E_BITS);
    pack(bits, &nbit, e_index, E_BITS);

    encode_lspds_scalar(lspd_indexes, lsps, LPC_ORD);
    for(i=0; i<LSPD_SCALAR_INDEXES; i++) {
	pack(bits, &nbit, lspd_indexes[i], lspd_bits(i));
    }
    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_3200
  AUTHOR......: David Rowe
  DATE CREATED: 13 Sep 2012

  Decodes a frame of 64 bits into 160 samples (20ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_3200(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[2];
    int     lspd_indexes[LPC_ORD];
    float   lsps[2][LPC_ORD];
    int     Wo_index, e_index;
    float   e[2];
    float   snr;
    float   ak[2][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<2; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 2 x 10ms
       frames */

    model[0].voiced = unpack(bits, &nbit, 1);
    model[1].voiced = unpack(bits, &nbit, 1);

    Wo_index = unpack(bits, &nbit, WO_BITS);
    model[1].Wo = decode_Wo(Wo_index, WO_BITS);
    model[1].L  = PI/model[1].Wo;

    e_index = unpack(bits, &nbit, E_BITS);
    e[1] = decode_energy(e_index, E_BITS);

    for(i=0; i<LSPD_SCALAR_INDEXES; i++) {
	lspd_indexes[i] = unpack(bits, &nbit, lspd_bits(i));
    }
    decode_lspds_scalar(&lsps[1][0], lspd_indexes, LPC_ORD);

    /* interpolate ------------------------------------------------*/

    /* Wo and energy are sampled every 20ms, so we interpolate just 1
       10ms frame between 20ms samples */

    interp_Wo(&model[0], &c2->prev_model_dec, &model[1]);
    e[0] = interp_energy(c2->prev_e_dec, e[1]);

    /* LSPs are sampled every 20ms so we interpolate the frame in
       between, then recover spectral amplitudes */

    interpolate_lsp_ver2(&lsps[0][0], c2->prev_lsps_dec, &lsps[1][0], 0.5, LPC_ORD);

    for(i=0; i<2; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[1];
    c2->prev_e_dec = e[1];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[1][i];
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_2400
  AUTHOR......: David Rowe
  DATE CREATED: 21/8/2010

  Encodes 160 speech samples (20ms of speech) into 48 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm twice.  On the
  first frame we just send the voicing bit.  On the second frame we
  send all model parameters.

  The bit allocation is:

    Parameter                      bits/frame
    --------------------------------------
    Harmonic magnitudes (LSPs)     36
    Joint VQ of Energy and Wo       8
    Voicing (10ms update)           2
    Spare                           2
    TOTAL                          48

\*---------------------------------------------------------------------------*/

void codec2_encode_2400(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   ak[LPC_ORD+1];
    float   lsps[LPC_ORD];
    float   e;
    int     WoE_index;
    int     lsp_indexes[LPC_ORD];
    int     i;
    int     spare = 0;
    unsigned int nbit = 0;

    assert(c2 != NULL);

    memset(bits, '\0', ((codec2_bits_per_frame(c2) + 7) / 8));

    /* first 10ms analysis frame - we just want voicing */

    analyse_one_frame(c2, &model, speech);
    pack(bits, &nbit, model.voiced, 1);

    /* second 10ms analysis frame */

    analyse_one_frame(c2, &model, &speech[N]);
    pack(bits, &nbit, model.voiced, 1);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    WoE_index = encode_WoE(&model, e, c2->xq_enc);
    pack(bits, &nbit, WoE_index, WO_E_BITS);

    encode_lsps_scalar(lsp_indexes, lsps, LPC_ORD);
    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	pack(bits, &nbit, lsp_indexes[i], lsp_bits(i));
    }
    pack(bits, &nbit, spare, 2);

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_2400
  AUTHOR......: David Rowe
  DATE CREATED: 21/8/2010

  Decodes frames of 48 bits into 160 samples (20ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_2400(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[2];
    int     lsp_indexes[LPC_ORD];
    float   lsps[2][LPC_ORD];
    int     WoE_index;
    float   e[2];
    float   snr;
    float   ak[2][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<2; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 2 x 10ms
       frames */

    model[0].voiced = unpack(bits, &nbit, 1);

    model[1].voiced = unpack(bits, &nbit, 1);
    WoE_index = unpack(bits, &nbit, WO_E_BITS);
    decode_WoE(&model[1], &e[1], c2->xq_dec, WoE_index);

    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	lsp_indexes[i] = unpack(bits, &nbit, lsp_bits(i));
    }
    decode_lsps_scalar(&lsps[1][0], lsp_indexes, LPC_ORD);
    check_lsp_order(&lsps[1][0], LPC_ORD);
    bw_expand_lsps(&lsps[1][0], LPC_ORD, 50.0, 100.0);

    /* interpolate ------------------------------------------------*/

    /* Wo and energy are sampled every 20ms, so we interpolate just 1
       10ms frame between 20ms samples */

    interp_Wo(&model[0], &c2->prev_model_dec, &model[1]);
    e[0] = interp_energy(c2->prev_e_dec, e[1]);

    /* LSPs are sampled every 20ms so we interpolate the frame in
       between, then recover spectral amplitudes */

    interpolate_lsp_ver2(&lsps[0][0], c2->prev_lsps_dec, &lsps[1][0], 0.5, LPC_ORD);
    for(i=0; i<2; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[1];
    c2->prev_e_dec = e[1];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[1][i];
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_1600
  AUTHOR......: David Rowe
  DATE CREATED: Feb 28 2013

  Encodes 320 speech samples (40ms of speech) into 64 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm 4 times:

  frame 0: voicing bit
  frame 1: voicing bit, Wo and E
  frame 2: voicing bit
  frame 3: voicing bit, Wo and E, scalar LSPs

  The bit allocation is:

    Parameter                      frame 2  frame 4   Total
    -------------------------------------------------------
    Harmonic magnitudes (LSPs)      0       36        36
    Pitch (Wo)                      7        7        14
    Energy                          5        5        10
    Voicing (10ms update)           2        2         4
    TOTAL                          14       50        64

\*---------------------------------------------------------------------------*/

void codec2_encode_1600(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD];
    float   ak[LPC_ORD+1];
    float   e;
    int     lsp_indexes[LPC_ORD];
    int     Wo_index, e_index;
    int     i;
    unsigned int nbit = 0;

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* frame 1: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, speech);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 2: - voicing, scalar Wo & E -------------------------------*/

    analyse_one_frame(c2, &model, &speech[N]);
    pack(bits, &nbit, model.voiced, 1);

    Wo_index = encode_Wo(model.Wo, WO_BITS);
    pack(bits, &nbit, Wo_index, WO_BITS);

    /* need to run this just to get LPC energy */
    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    e_index = encode_energy(e, E_BITS);
    pack(bits, &nbit, e_index, E_BITS);

    /* frame 3: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, &speech[2*N]);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 4: - voicing, scalar Wo & E, scalar LSPs ------------------*/

    analyse_one_frame(c2, &model, &speech[3*N]);
    pack(bits, &nbit, model.voiced, 1);

    Wo_index = encode_Wo(model.Wo, WO_BITS);
    pack(bits, &nbit, Wo_index, WO_BITS);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    e_index = encode_energy(e, E_BITS);
    pack(bits, &nbit, e_index, E_BITS);

    encode_lsps_scalar(lsp_indexes, lsps, LPC_ORD);
    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	pack(bits, &nbit, lsp_indexes[i], lsp_bits(i));
    }

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_1600
  AUTHOR......: David Rowe
  DATE CREATED: 11 May 2012

  Decodes frames of 64 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_1600(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[4];
    int     lsp_indexes[LPC_ORD];
    float   lsps[4][LPC_ORD];
    int     Wo_index, e_index;
    float   e[4];
    float   snr;
    float   ak[4][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 4 x 10ms
       frames */

    model[0].voiced = unpack(bits, &nbit, 1);

    model[1].voiced = unpack(bits, &nbit, 1);
    Wo_index = unpack(bits, &nbit, WO_BITS);
    model[1].Wo = decode_Wo(Wo_index, WO_BITS);
    model[1].L  = PI/model[1].Wo;

    e_index = unpack(bits, &nbit, E_BITS);
    e[1] = decode_energy(e_index, E_BITS);

    model[2].voiced = unpack(bits, &nbit, 1);

    model[3].voiced = unpack(bits, &nbit, 1);
    Wo_index = unpack(bits, &nbit, WO_BITS);
    model[3].Wo = decode_Wo(Wo_index, WO_BITS);
    model[3].L  = PI/model[3].Wo;

    e_index = unpack(bits, &nbit, E_BITS);
    e[3] = decode_energy(e_index, E_BITS);

    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	lsp_indexes[i] = unpack(bits, &nbit, lsp_bits(i));
    }
    decode_lsps_scalar(&lsps[3][0], lsp_indexes, LPC_ORD);
    check_lsp_order(&lsps[3][0], LPC_ORD);
    bw_expand_lsps(&lsps[3][0], LPC_ORD, 50.0, 100.0);

    /* interpolate ------------------------------------------------*/

    /* Wo and energy are sampled every 20ms, so we interpolate just 1
       10ms frame between 20ms samples */

    interp_Wo(&model[0], &c2->prev_model_dec, &model[1]);
    e[0] = interp_energy(c2->prev_e_dec, e[1]);
    interp_Wo(&model[2], &model[1], &model[3]);
    e[2] = interp_energy(e[1], e[3]);

    /* LSPs are sampled every 40ms so we interpolate the 3 frames in
       between, then recover spectral amplitudes */

    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD);
    }
    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];

}

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_1400
  AUTHOR......: David Rowe
  DATE CREATED: May 11 2012

  Encodes 320 speech samples (40ms of speech) into 56 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm 4 times:

  frame 0: voicing bit
  frame 1: voicing bit, joint VQ of Wo and E
  frame 2: voicing bit
  frame 3: voicing bit, joint VQ of Wo and E, scalar LSPs

  The bit allocation is:

    Parameter                      frame 2  frame 4   Total
    -------------------------------------------------------
    Harmonic magnitudes (LSPs)      0       36        36
    Energy+Wo                       8        8        16
    Voicing (10ms update)           2        2         4
    TOTAL                          10       46        56

\*---------------------------------------------------------------------------*/

void codec2_encode_1400(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD];
    float   ak[LPC_ORD+1];
    float   e;
    int     lsp_indexes[LPC_ORD];
    int     WoE_index;
    int     i;
    unsigned int nbit = 0;

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* frame 1: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, speech);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 2: - voicing, joint Wo & E -------------------------------*/

    analyse_one_frame(c2, &model, &speech[N]);
    pack(bits, &nbit, model.voiced, 1);

    /* need to run this just to get LPC energy */
    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);

    WoE_index = encode_WoE(&model, e, c2->xq_enc);
    pack(bits, &nbit, WoE_index, WO_E_BITS);

    /* frame 3: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, &speech[2*N]);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 4: - voicing, joint Wo & E, scalar LSPs ------------------*/

    analyse_one_frame(c2, &model, &speech[3*N]);
    pack(bits, &nbit, model.voiced, 1);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    WoE_index = encode_WoE(&model, e, c2->xq_enc);
    pack(bits, &nbit, WoE_index, WO_E_BITS);

    encode_lsps_scalar(lsp_indexes, lsps, LPC_ORD);
    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	pack(bits, &nbit, lsp_indexes[i], lsp_bits(i));
    }

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_1400
  AUTHOR......: David Rowe
  DATE CREATED: 11 May 2012

  Decodes frames of 56 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_1400(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[4];
    int     lsp_indexes[LPC_ORD];
    float   lsps[4][LPC_ORD];
    int     WoE_index;
    float   e[4];
    float   snr;
    float   ak[4][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 4 x 10ms
       frames */

    model[0].voiced = unpack(bits, &nbit, 1);

    model[1].voiced = unpack(bits, &nbit, 1);
    WoE_index = unpack(bits, &nbit, WO_E_BITS);
    decode_WoE(&model[1], &e[1], c2->xq_dec, WoE_index);

    model[2].voiced = unpack(bits, &nbit, 1);

    model[3].voiced = unpack(bits, &nbit, 1);
    WoE_index = unpack(bits, &nbit, WO_E_BITS);
    decode_WoE(&model[3], &e[3], c2->xq_dec, WoE_index);

    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	lsp_indexes[i] = unpack(bits, &nbit, lsp_bits(i));
    }
    decode_lsps_scalar(&lsps[3][0], lsp_indexes, LPC_ORD);
    check_lsp_order(&lsps[3][0], LPC_ORD);
    bw_expand_lsps(&lsps[3][0], LPC_ORD, 50.0, 100.0);

    /* interpolate ------------------------------------------------*/

    /* Wo and energy are sampled every 20ms, so we interpolate just 1
       10ms frame between 20ms samples */

    interp_Wo(&model[0], &c2->prev_model_dec, &model[1]);
    e[0] = interp_energy(c2->prev_e_dec, e[1]);
    interp_Wo(&model[2], &model[1], &model[3]);
    e[2] = interp_energy(e[1], e[3]);

    /* LSPs are sampled every 40ms so we interpolate the 3 frames in
       between, then recover spectral amplitudes */

    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD);
    }
    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];

}

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_1300
  AUTHOR......: David Rowe
  DATE CREATED: March 14 2013

  Encodes 320 speech samples (40ms of speech) into 52 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm 4 times:

  frame 0: voicing bit
  frame 1: voicing bit,
  frame 2: voicing bit
  frame 3: voicing bit, Wo and E, scalar LSPs

  The bit allocation is:

    Parameter                      frame 2  frame 4   Total
    -------------------------------------------------------
    Harmonic magnitudes (LSPs)      0       36        36
    Pitch (Wo)                      0        7         7
    Energy                          0        5         5
    Voicing (10ms update)           2        2         4
    TOTAL                           2       50        52

\*---------------------------------------------------------------------------*/

void codec2_encode_1300(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD];
    float   ak[LPC_ORD+1];
    float   e;
    int     lsp_indexes[LPC_ORD];
    int     Wo_index, e_index;
    int     i;
    unsigned int nbit = 0;
    #ifdef PROFILE
    unsigned int quant_start;
    #endif

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* frame 1: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, speech);
    pack_natural_or_gray(bits, &nbit, model.voiced, 1, c2->gray);

    /* frame 2: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, &speech[N]);
    pack_natural_or_gray(bits, &nbit, model.voiced, 1, c2->gray);

    /* frame 3: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, &speech[2*N]);
    pack_natural_or_gray(bits, &nbit, model.voiced, 1, c2->gray);

    /* frame 4: - voicing, scalar Wo & E, scalar LSPs ------------------*/

    analyse_one_frame(c2, &model, &speech[3*N]);
    pack_natural_or_gray(bits, &nbit, model.voiced, 1, c2->gray);

    Wo_index = encode_Wo(model.Wo, WO_BITS);
    pack_natural_or_gray(bits, &nbit, Wo_index, WO_BITS, c2->gray);

    #ifdef PROFILE
    quant_start = machdep_profile_sample();
    #endif
    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    e_index = encode_energy(e, E_BITS);
    pack_natural_or_gray(bits, &nbit, e_index, E_BITS, c2->gray);

    encode_lsps_scalar(lsp_indexes, lsps, LPC_ORD);
    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	pack_natural_or_gray(bits, &nbit, lsp_indexes[i], lsp_bits(i), c2->gray);
    }
    #ifdef PROFILE
    machdep_profile_sample_and_log(quant_start, "    quant/packing");
    #endif

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_1300
  AUTHOR......: David Rowe
  DATE CREATED: 11 May 2012

  Decodes frames of 52 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/
static int frames;
void codec2_decode_1300(struct CODEC2 *c2, short speech[], const unsigned char * bits, float ber_est)
{
    MODEL   model[4];
    int     lsp_indexes[LPC_ORD];
    float   lsps[4][LPC_ORD];
    int     Wo_index, e_index;
    float   e[4];
    float   snr;
    float   ak[4][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];
    PROFILE_VAR(recover_start);

    assert(c2 != NULL);
    frames+= 4;
    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 4 x 10ms
       frames */

    model[0].voiced = unpack_natural_or_gray(bits, &nbit, 1, c2->gray);
    model[1].voiced = unpack_natural_or_gray(bits, &nbit, 1, c2->gray);
    model[2].voiced = unpack_natural_or_gray(bits, &nbit, 1, c2->gray);
    model[3].voiced = unpack_natural_or_gray(bits, &nbit, 1, c2->gray);

    Wo_index = unpack_natural_or_gray(bits, &nbit, WO_BITS, c2->gray);
    model[3].Wo = decode_Wo(Wo_index, WO_BITS);
    model[3].L  = PI/model[3].Wo;

    e_index = unpack_natural_or_gray(bits, &nbit, E_BITS, c2->gray);
    e[3] = decode_energy(e_index, E_BITS);

    for(i=0; i<LSP_SCALAR_INDEXES; i++) {
	lsp_indexes[i] = unpack_natural_or_gray(bits, &nbit, lsp_bits(i), c2->gray);
    }
    decode_lsps_scalar(&lsps[3][0], lsp_indexes, LPC_ORD);
    check_lsp_order(&lsps[3][0], LPC_ORD);
    bw_expand_lsps(&lsps[3][0], LPC_ORD, 50.0, 100.0);

    if (ber_est > 0.15) {
        model[0].voiced =  model[1].voiced = model[2].voiced = model[3].voiced = 0;
        e[3] = decode_energy(10, E_BITS);
        bw_expand_lsps(&lsps[3][0], LPC_ORD, 200.0, 200.0);
        fprintf(stderr, "soft mute\n");
    }

    /* interpolate ------------------------------------------------*/

    /* Wo, energy, and LSPs are sampled every 40ms so we interpolate
       the 3 frames in between */

    PROFILE_SAMPLE(recover_start);
    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD);
        interp_Wo2(&model[i], &c2->prev_model_dec, &model[3], weight);
        e[i] = interp_energy2(c2->prev_e_dec, e[3],weight);
    }

    /* then recover spectral amplitudes */

    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }
    /*
    for(i=0; i<4; i++) {
        printf("%d Wo: %f L: %d v: %d\n", frames, model[i].Wo, model[i].L, model[i].voiced);
    }
    if (frames == 4*50)
        exit(0);
    */
    PROFILE_SAMPLE_AND_LOG2(recover_start, "    recover");
    #ifdef DUMP
    dump_lsp_(&lsps[3][0]);
    dump_ak_(&ak[3][0], LPC_ORD);
    #endif

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];

}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_1200
  AUTHOR......: David Rowe
  DATE CREATED: Nov 14 2011

  Encodes 320 speech samples (40ms of speech) into 48 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm four times:

  frame 0: voicing bit
  frame 1: voicing bit, joint VQ of Wo and E
  frame 2: voicing bit
  frame 3: voicing bit, joint VQ of Wo and E, VQ LSPs

  The bit allocation is:

    Parameter                      frame 2  frame 4   Total
    -------------------------------------------------------
    Harmonic magnitudes (LSPs)      0       27        27
    Energy+Wo                       8        8        16
    Voicing (10ms update)           2        2         4
    Spare                           0        1         1
    TOTAL                          10       38        48

\*---------------------------------------------------------------------------*/

void codec2_encode_1200(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD];
    float   lsps_[LPC_ORD];
    float   ak[LPC_ORD+1];
    float   e;
    int     lsp_indexes[LPC_ORD];
    int     WoE_index;
    int     i;
    int     spare = 0;
    unsigned int nbit = 0;

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* frame 1: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, speech);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 2: - voicing, joint Wo & E -------------------------------*/

    analyse_one_frame(c2, &model, &speech[N]);
    pack(bits, &nbit, model.voiced, 1);

    /* need to run this just to get LPC energy */
    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);

    WoE_index = encode_WoE(&model, e, c2->xq_enc);
    pack(bits, &nbit, WoE_index, WO_E_BITS);

    /* frame 3: - voicing ---------------------------------------------*/

    analyse_one_frame(c2, &model, &speech[2*N]);
    pack(bits, &nbit, model.voiced, 1);

    /* frame 4: - voicing, joint Wo & E, scalar LSPs ------------------*/

    analyse_one_frame(c2, &model, &speech[3*N]);
    pack(bits, &nbit, model.voiced, 1);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD);
    WoE_index = encode_WoE(&model, e, c2->xq_enc);
    pack(bits, &nbit, WoE_index, WO_E_BITS);

    encode_lsps_vq(lsp_indexes, lsps, lsps_, LPC_ORD);
    for(i=0; i<LSP_PRED_VQ_INDEXES; i++) {
	pack(bits, &nbit, lsp_indexes[i], lsp_pred_vq_bits(i));
    }
    pack(bits, &nbit, spare, 1);

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_1200
  AUTHOR......: David Rowe
  DATE CREATED: 14 Feb 2012

  Decodes frames of 48 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_1200(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[4];
    int     lsp_indexes[LPC_ORD];
    float   lsps[4][LPC_ORD];
    int     WoE_index;
    float   e[4];
    float   snr;
    float   ak[4][LPC_ORD+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    /* this will partially fill the model params for the 4 x 10ms
       frames */

    model[0].voiced = unpack(bits, &nbit, 1);

    model[1].voiced = unpack(bits, &nbit, 1);
    WoE_index = unpack(bits, &nbit, WO_E_BITS);
    decode_WoE(&model[1], &e[1], c2->xq_dec, WoE_index);

    model[2].voiced = unpack(bits, &nbit, 1);

    model[3].voiced = unpack(bits, &nbit, 1);
    WoE_index = unpack(bits, &nbit, WO_E_BITS);
    decode_WoE(&model[3], &e[3], c2->xq_dec, WoE_index);

    for(i=0; i<LSP_PRED_VQ_INDEXES; i++) {
	lsp_indexes[i] = unpack(bits, &nbit, lsp_pred_vq_bits(i));
    }
    decode_lsps_vq(lsp_indexes, &lsps[3][0], LPC_ORD , 0);
    check_lsp_order(&lsps[3][0], LPC_ORD);
    bw_expand_lsps(&lsps[3][0], LPC_ORD, 50.0, 100.0);

    /* interpolate ------------------------------------------------*/

    /* Wo and energy are sampled every 20ms, so we interpolate just 1
       10ms frame between 20ms samples */

    interp_Wo(&model[0], &c2->prev_model_dec, &model[1]);
    e[0] = interp_energy(c2->prev_e_dec, e[1]);
    interp_Wo(&model[2], &model[1], &model[3]);
    e[2] = interp_energy(e[1], e[3]);

    /* LSPs are sampled every 40ms so we interpolate the 3 frames in
       between, then recover spectral amplitudes */

    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD);
    }
    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];
}


#ifndef CORTEX_M4
/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_700
  AUTHOR......: David Rowe
  DATE CREATED: April 2015

  Encodes 320 speech samples (40ms of speech) into 28 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm four times:

  frame 0: nothing
  frame 1: nothing
  frame 2: nothing
  frame 3: voicing bit, scalar Wo and E, 17 bit LSP MEL scalar, 2 spare

  The bit allocation is:

    Parameter                      frames 1-3   frame 4   Total
    -----------------------------------------------------------
    Harmonic magnitudes (LSPs)          0         17        17
    Energy                              0          3         3
    log Wo                              0          5         5
    Voicing                             0          1         1
    spare                               0          2         2
    TOTAL                               0         28        28

\*---------------------------------------------------------------------------*/

void codec2_encode_700(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD_LOW];
    float   mel[LPC_ORD_LOW];
    float   ak[LPC_ORD_LOW+1];
    float   e, f;
    int     indexes[LPC_ORD_LOW];
    int     Wo_index, e_index, i;
    unsigned int nbit = 0;
    float   bpf_out[4*N];
    short   bpf_speech[4*N];
    int     spare = 0;

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* band pass filter */

    for(i=0; i<BPF_N; i++)
        c2->bpf_buf[i] = c2->bpf_buf[4*N+i];
    for(i=0; i<4*N; i++)
        c2->bpf_buf[BPF_N+i] = speech[i];
    inverse_filter(&c2->bpf_buf[BPF_N], bpf, 4*N, bpf_out, BPF_N-1);
    for(i=0; i<4*N; i++)
        bpf_speech[i] = bpf_out[i];

    /* frame 1 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, bpf_speech);

    /* frame 2 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, &bpf_speech[N]);

    /* frame 3 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, &bpf_speech[2*N]);

    /* frame 4: - voicing, scalar Wo & E, scalar LSPs -----------------*/

    analyse_one_frame(c2, &model, &bpf_speech[3*N]);
    pack(bits, &nbit, model.voiced, 1);
    Wo_index = encode_log_Wo(model.Wo, 5);
    pack_natural_or_gray(bits, &nbit, Wo_index, 5, c2->gray);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD_LOW);
    e_index = encode_energy(e, 3);
    pack_natural_or_gray(bits, &nbit, e_index, 3, c2->gray);

    for(i=0; i<LPC_ORD_LOW; i++) {
        f = (4000.0/PI)*lsps[i];
        mel[i] = floor(2595.0*log10(1.0 + f/700.0) + 0.5);
    }
    encode_mels_scalar(indexes, mel, LPC_ORD_LOW);

    for(i=0; i<LPC_ORD_LOW; i++) {
        pack_natural_or_gray(bits, &nbit, indexes[i], mel_bits(i), c2->gray);
    }

    pack_natural_or_gray(bits, &nbit, spare, 2, c2->gray);

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_700
  AUTHOR......: David Rowe
  DATE CREATED: April 2015

  Decodes frames of 28 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_700(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[4];
    int     indexes[LPC_ORD_LOW];
    float   mel[LPC_ORD_LOW];
    float   lsps[4][LPC_ORD_LOW];
    int     Wo_index, e_index;
    float   e[4];
    float   snr, f_;
    float   ak[4][LPC_ORD_LOW+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    model[3].voiced = unpack(bits, &nbit, 1);
    model[0].voiced = model[1].voiced = model[2].voiced = model[3].voiced;

    Wo_index = unpack_natural_or_gray(bits, &nbit, 5, c2->gray);
    model[3].Wo = decode_log_Wo(Wo_index, 5);
    model[3].L  = PI/model[3].Wo;

    e_index = unpack_natural_or_gray(bits, &nbit, 3, c2->gray);
    e[3] = decode_energy(e_index, 3);

    for(i=0; i<LPC_ORD_LOW; i++) {
        indexes[i] = unpack_natural_or_gray(bits, &nbit, mel_bits(i), c2->gray);
    }

    decode_mels_scalar(mel, indexes, LPC_ORD_LOW);
    for(i=0; i<LPC_ORD_LOW; i++) {
        f_ = 700.0*( pow(10.0, (float)mel[i]/2595.0) - 1.0);
        lsps[3][i] = f_*(PI/4000.0);
        //printf("lsps[3][%d]  %f\n", i, lsps[3][i]);
    }

    check_lsp_order(&lsps[3][0], LPC_ORD_LOW);
    bw_expand_lsps(&lsps[3][0], LPC_ORD_LOW, 50.0, 100.0);

    #ifdef MASK_NOT_FOR_NOW
    /* first pass at soft decn error masking, needs further work      */
    /* If soft dec info available expand further for low power frames */

    if (c2->softdec) {
        float e = 0.0;
        for(i=9; i<9+17; i++)
            e += c2->softdec[i]*c2->softdec[i];
        e /= 6.0;
        //fprintf(stderr, "e: %f\n", e);
        //if (e < 0.3)
        //      bw_expand_lsps(&lsps[3][0], LPC_ORD_LOW, 150.0, 300.0);
    }
    #endif

    /* interpolate ------------------------------------------------*/

    /* LSPs, Wo, and energy are sampled every 40ms so we interpolate
       the 3 frames in between, then recover spectral amplitudes */

    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD_LOW);
        interp_Wo2(&model[i], &c2->prev_model_dec, &model[3], weight);
        e[i] = interp_energy2(c2->prev_e_dec, e[3],weight);
    }
    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD_LOW);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD_LOW, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    #ifdef DUMP
    dump_lsp_(&lsps[3][0]);
    dump_ak_(&ak[3][0], LPC_ORD_LOW);
    dump_model(&model[3]);
    if (c2->softdec)
        dump_softdec(c2->softdec, nbit);
    #endif

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD_LOW; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_encode_700b
  AUTHOR......: David Rowe
  DATE CREATED: August 2015

  Version b of 700 bit/s codec.  After some experiments over the air I
  wanted was unhappy with the rate 700 codec so spent a few weeks
  trying to improve the speech quality. This version uses a wider BPF
  and vector quantised mel-lsps.

  Encodes 320 speech samples (40ms of speech) into 28 bits.

  The codec2 algorithm actually operates internally on 10ms (80
  sample) frames, so we run the encoding algorithm four times:

  frame 0: nothing
  frame 1: nothing
  frame 2: nothing
  frame 3: voicing bit, 5 bit scalar Wo and 3 bit E, 18 bit LSP MEL VQ,
           1 spare

  The bit allocation is:

    Parameter                      frames 1-3   frame 4   Total
    -----------------------------------------------------------
    Harmonic magnitudes (LSPs)          0         18        18
    Energy                              0          3         3
    log Wo                              0          5         5
    Voicing                             0          1         1
    spare                               0          1         1
    TOTAL                               0         28        28

\*---------------------------------------------------------------------------*/

void codec2_encode_700b(struct CODEC2 *c2, unsigned char * bits, short speech[])
{
    MODEL   model;
    float   lsps[LPC_ORD_LOW];
    float   mel[LPC_ORD_LOW];
    float   mel_[LPC_ORD_LOW];
    float   ak[LPC_ORD_LOW+1];
    float   e, f;
    int     indexes[3];
    int     Wo_index, e_index, i;
    unsigned int nbit = 0;
    float   bpf_out[4*N];
    short   bpf_speech[4*N];
    int     spare = 0;

    assert(c2 != NULL);

    memset(bits, '\0',  ((codec2_bits_per_frame(c2) + 7) / 8));

    /* band pass filter */

    for(i=0; i<BPF_N; i++)
        c2->bpf_buf[i] = c2->bpf_buf[4*N+i];
    for(i=0; i<4*N; i++)
        c2->bpf_buf[BPF_N+i] = speech[i];
    inverse_filter(&c2->bpf_buf[BPF_N], bpfb, 4*N, bpf_out, BPF_N-1);
    for(i=0; i<4*N; i++)
        bpf_speech[i] = bpf_out[i];

    /* frame 1 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, bpf_speech);

    /* frame 2 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, &bpf_speech[N]);

    /* frame 3 --------------------------------------------------------*/

    analyse_one_frame(c2, &model, &bpf_speech[2*N]);

    /* frame 4: - voicing, scalar Wo & E, VQ mel LSPs -----------------*/

    analyse_one_frame(c2, &model, &bpf_speech[3*N]);
    pack(bits, &nbit, model.voiced, 1);
    Wo_index = encode_log_Wo(model.Wo, 5);
    pack_natural_or_gray(bits, &nbit, Wo_index, 5, c2->gray);

    e = speech_to_uq_lsps(lsps, ak, c2->Sn, c2->w, LPC_ORD_LOW);
    e_index = encode_energy(e, 3);
    pack_natural_or_gray(bits, &nbit, e_index, 3, c2->gray);

    for(i=0; i<LPC_ORD_LOW; i++) {
        f = (4000.0/PI)*lsps[i];
        mel[i] = floor(2595.0*log10(1.0 + f/700.0) + 0.5);
    }
    lspmelvq_mbest_encode(indexes, mel, mel_, LPC_ORD_LOW, 5);

    for(i=0; i<3; i++) {
        pack_natural_or_gray(bits, &nbit, indexes[i], lspmelvq_cb_bits(i), c2->gray);
    }

    pack_natural_or_gray(bits, &nbit, spare, 1, c2->gray);

    assert(nbit == (unsigned)codec2_bits_per_frame(c2));
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_decode_700b
  AUTHOR......: David Rowe
  DATE CREATED: August 2015

  Decodes frames of 28 bits into 320 samples (40ms) of speech.

\*---------------------------------------------------------------------------*/

void codec2_decode_700b(struct CODEC2 *c2, short speech[], const unsigned char * bits)
{
    MODEL   model[4];
    int     indexes[3];
    float   mel[LPC_ORD_LOW];
    float   lsps[4][LPC_ORD_LOW];
    int     Wo_index, e_index;
    float   e[4];
    float   snr, f_;
    float   ak[4][LPC_ORD_LOW+1];
    int     i,j;
    unsigned int nbit = 0;
    float   weight;
    COMP    Aw[FFT_ENC];

    assert(c2 != NULL);

    /* only need to zero these out due to (unused) snr calculation */

    for(i=0; i<4; i++)
	for(j=1; j<=MAX_AMP; j++)
	    model[i].A[j] = 0.0;

    /* unpack bits from channel ------------------------------------*/

    model[3].voiced = unpack(bits, &nbit, 1);
    model[0].voiced = model[1].voiced = model[2].voiced = model[3].voiced;

    Wo_index = unpack_natural_or_gray(bits, &nbit, 5, c2->gray);
    model[3].Wo = decode_log_Wo(Wo_index, 5);
    model[3].L  = PI/model[3].Wo;

    e_index = unpack_natural_or_gray(bits, &nbit, 3, c2->gray);
    e[3] = decode_energy(e_index, 3);

    for(i=0; i<3; i++) {
        indexes[i] = unpack_natural_or_gray(bits, &nbit, lspmelvq_cb_bits(i), c2->gray);
    }

    lspmelvq_decode(indexes, mel, LPC_ORD_LOW);

    #define MEL_ROUND 10
    for(i=1; i<LPC_ORD_LOW; i++) {
        if (mel[i] <= mel[i-1]+MEL_ROUND) {
            mel[i]+=MEL_ROUND/2;
            mel[i-1]-=MEL_ROUND/2;
            i = 1;
        }
    }

    for(i=0; i<LPC_ORD_LOW; i++) {
        f_ = 700.0*( pow(10.0, (float)mel[i]/2595.0) - 1.0);
        lsps[3][i] = f_*(PI/4000.0);
        //printf("lsps[3][%d]  %f\n", i, lsps[3][i]);
    }

    /* interpolate ------------------------------------------------*/

    /* LSPs, Wo, and energy are sampled every 40ms so we interpolate
       the 3 frames in between, then recover spectral amplitudes */

    for(i=0, weight=0.25; i<3; i++, weight += 0.25) {
	interpolate_lsp_ver2(&lsps[i][0], c2->prev_lsps_dec, &lsps[3][0], weight, LPC_ORD_LOW);
        interp_Wo2(&model[i], &c2->prev_model_dec, &model[3], weight);
        e[i] = interp_energy2(c2->prev_e_dec, e[3],weight);
    }
    for(i=0; i<4; i++) {
	lsp_to_lpc(&lsps[i][0], &ak[i][0], LPC_ORD_LOW);
	aks_to_M2(c2->fft_fwd_cfg, &ak[i][0], LPC_ORD_LOW, &model[i], e[i], &snr, 0, 0,
                  c2->lpc_pf, c2->bass_boost, c2->beta, c2->gamma, Aw);
	apply_lpc_correction(&model[i]);
	synthesise_one_frame(c2, &speech[N*i], &model[i], Aw);
    }

    #ifdef DUMP
    dump_lsp_(&lsps[3][0]);
    dump_ak_(&ak[3][0], LPC_ORD_LOW);
    dump_model(&model[3]);
    if (c2->softdec)
        dump_softdec(c2->softdec, nbit);
    #endif

    /* update memories for next frame ----------------------------*/

    c2->prev_model_dec = model[3];
    c2->prev_e_dec = e[3];
    for(i=0; i<LPC_ORD_LOW; i++)
	c2->prev_lsps_dec[i] = lsps[3][i];
}
#endif

/*---------------------------------------------------------------------------*\

  FUNCTION....: codec2_get_energy()
  AUTHOR......: Jeroen Vreeken
  DATE CREATED: 08/03/2016

  Extract energy value from an encoded frame.

\*---------------------------------------------------------------------------*/

float codec2_get_energy(struct CODEC2 *c2, const unsigned char *bits)
{
    assert(c2 != NULL);
    assert(
	   (c2->mode == CODEC2_MODE_3200) ||
	   (c2->mode == CODEC2_MODE_2400) ||
	   (c2->mode == CODEC2_MODE_1600) ||
	   (c2->mode == CODEC2_MODE_1400) ||
	   (c2->mode == CODEC2_MODE_1300) ||
	   (c2->mode == CODEC2_MODE_1200) ||
	   (c2->mode == CODEC2_MODE_700) ||
	   (c2->mode == CODEC2_MODE_700B)
	   );
    MODEL model;
    float xq_dec[2] = {};
    int e_index, WoE_index;
    float e;
    unsigned int nbit;

    if (c2->mode == CODEC2_MODE_3200) {
        nbit = 1 + 1 + WO_BITS;
	e_index = unpack(bits, &nbit, E_BITS);
        e = decode_energy(e_index, E_BITS);
    }
    if (c2->mode == CODEC2_MODE_2400) {
        nbit = 1 + 1;
        WoE_index = unpack(bits, &nbit, WO_E_BITS);
        decode_WoE(&model, &e, xq_dec, WoE_index);
    }
    if (c2->mode == CODEC2_MODE_1600) {
        nbit = 1 + 1 + WO_BITS;
        e_index = unpack(bits, &nbit, E_BITS);
        e = decode_energy(e_index, E_BITS);
    }
    if (c2->mode == CODEC2_MODE_1400) {
        nbit = 1 + 1;
        WoE_index = unpack(bits, &nbit, WO_E_BITS);
        decode_WoE(&model, &e, xq_dec, WoE_index);
    }
    if (c2->mode == CODEC2_MODE_1300) {
        nbit = 1 + 1 + 1 + 1 + WO_BITS;
        e_index = unpack_natural_or_gray(bits, &nbit, E_BITS, c2->gray);
        e = decode_energy(e_index, E_BITS);
    }
    if (c2->mode == CODEC2_MODE_1200) {
        nbit = 1 + 1;
        WoE_index = unpack(bits, &nbit, WO_E_BITS);
        decode_WoE(&model, &e, xq_dec, WoE_index);
    }
    if (c2->mode == CODEC2_MODE_700) {
        nbit = 1 + 5;
        e_index = unpack_natural_or_gray(bits, &nbit, 3, c2->gray);
        e = decode_energy(e_index, 3);
    }
    if (c2->mode == CODEC2_MODE_700B) {
        nbit = 1 + 5;
        e_index = unpack_natural_or_gray(bits, &nbit, 3, c2->gray);
        e = decode_energy(e_index, 3);
    }

    return e;
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: synthesise_one_frame()
  AUTHOR......: David Rowe
  DATE CREATED: 23/8/2010

  Synthesise 80 speech samples (10ms) from model parameters.

\*---------------------------------------------------------------------------*/

void synthesise_one_frame(struct CODEC2 *c2, short speech[], MODEL *model, COMP Aw[])
{
    int     i;
    PROFILE_VAR(phase_start, pf_start, synth_start);

    #ifdef DUMP
    dump_quantised_model(model);
    #endif

    PROFILE_SAMPLE(phase_start);

    phase_synth_zero_order(c2->fft_fwd_cfg, model, &c2->ex_phase, Aw);

    PROFILE_SAMPLE_AND_LOG(pf_start, phase_start, "    phase_synth");

    postfilter(model, &c2->bg_est);

    PROFILE_SAMPLE_AND_LOG(synth_start, pf_start, "    postfilter");

    synthesise(c2->fft_inv_cfg, c2->Sn_, model, c2->Pn, 1);

    PROFILE_SAMPLE_AND_LOG2(synth_start, "    synth");

    ear_protection(c2->Sn_, N);

    for(i=0; i<N; i++) {
	if (c2->Sn_[i] > 32767.0)
	    speech[i] = 32767;
	else if (c2->Sn_[i] < -32767.0)
	    speech[i] = -32767;
	else
	    speech[i] = c2->Sn_[i];
    }

}

/*---------------------------------------------------------------------------*\

  FUNCTION....: analyse_one_frame()
  AUTHOR......: David Rowe
  DATE CREATED: 23/8/2010

  Extract sinusoidal model parameters from 80 speech samples (10ms of
  speech).

\*---------------------------------------------------------------------------*/

void analyse_one_frame(struct CODEC2 *c2, MODEL *model, short speech[])
{
    COMP    Sw[FFT_ENC];
    COMP    Sw_[FFT_ENC];
    COMP    Ew[FFT_ENC];
    float   pitch;
    int     i;
    PROFILE_VAR(dft_start, nlp_start, model_start, two_stage, estamps);

    /* Read input speech */

    for(i=0; i<M-N; i++)
      c2->Sn[i] = c2->Sn[i+N];
    for(i=0; i<N; i++)
      c2->Sn[i+M-N] = speech[i];

    PROFILE_SAMPLE(dft_start);
    dft_speech(c2->fft_fwd_cfg, Sw, c2->Sn, c2->w);
    PROFILE_SAMPLE_AND_LOG(nlp_start, dft_start, "    dft_speech");

    /* Estimate pitch */

    nlp(c2->nlp,c2->Sn,N,P_MIN,P_MAX,&pitch,Sw, c2->W, &c2->prev_Wo_enc);
    PROFILE_SAMPLE_AND_LOG(model_start, nlp_start, "    nlp");

    model->Wo = TWO_PI/pitch;
    model->L = PI/model->Wo;

    /* estimate model parameters */

    two_stage_pitch_refinement(model, Sw);
    PROFILE_SAMPLE_AND_LOG(two_stage, model_start, "    two_stage");
    estimate_amplitudes(model, Sw, c2->W, 0);
    PROFILE_SAMPLE_AND_LOG(estamps, two_stage, "    est_amps");
    est_voicing_mbe(model, Sw, c2->W, Sw_, Ew);
    c2->prev_Wo_enc = model->Wo;
    PROFILE_SAMPLE_AND_LOG2(estamps, "    est_voicing");
    #ifdef DUMP
    dump_model(model);
    #endif
}

/*---------------------------------------------------------------------------*\

  FUNCTION....: ear_protection()
  AUTHOR......: David Rowe
  DATE CREATED: Nov 7 2012

  Limits output level to protect ears when there are bit errors or the input
  is overdriven.  This doesn't correct or mask bit errors, just reduces the
  worst of their damage.

\*---------------------------------------------------------------------------*/

static void ear_protection(float in_out[], int n) {
    float max_sample, over, gain;
    int   i;

    /* find maximum sample in frame */

    max_sample = 0.0;
    for(i=0; i<n; i++)
        if (in_out[i] > max_sample)
            max_sample = in_out[i];

    /* determine how far above set point */

    over = max_sample/30000.0;

    /* If we are x dB over set point we reduce level by 2x dB, this
       attenuates major excursions in amplitude (likely to be caused
       by bit errors) more than smaller ones */

    if (over > 1.0) {
        gain = 1.0/(over*over);
        //fprintf(stderr, "gain: %f\n", gain);
        for(i=0; i<n; i++)
            in_out[i] *= gain;
    }
}

void codec2_set_lpc_post_filter(struct CODEC2 *c2, int enable, int bass_boost, float beta, float gamma)
{
    assert((beta >= 0.0) && (beta <= 1.0));
    assert((gamma >= 0.0) && (gamma <= 1.0));
    c2->lpc_pf = enable;
    c2->bass_boost = bass_boost;
    c2->beta = beta;
    c2->gamma = gamma;
}

/*
   Allows optional stealing of one of the voicing bits for use as a
   spare bit, only 1300 & 1400 & 1600 bit/s supported for now.
   Experimental method of sending voice/data frames for FreeDV.
*/

int codec2_get_spare_bit_index(struct CODEC2 *c2)
{
    assert(c2 != NULL);

    switch(c2->mode) {
    case CODEC2_MODE_1300:
        return 2; // bit 2 (3th bit) is v2 (third voicing bit)
        break;
    case CODEC2_MODE_1400:
        return 10; // bit 10 (11th bit) is v2 (third voicing bit)
        break;
    case CODEC2_MODE_1600:
        return 15; // bit 15 (16th bit) is v2 (third voicing bit)
        break;
    case CODEC2_MODE_700:
        return 26; // bits 26 and 27 are spare
        break;
    case CODEC2_MODE_700B:
        return 27; // bit 27 is spare
        break;
    }

    return -1;
}

/*
   Reconstructs the spare voicing bit.  Note works on unpacked bits
   for convenience.
*/

int codec2_rebuild_spare_bit(struct CODEC2 *c2, int unpacked_bits[])
{
    int v1,v3;

    assert(c2 != NULL);

    v1 = unpacked_bits[1];

    switch(c2->mode) {
    case CODEC2_MODE_1300:

        v3 = unpacked_bits[1+1+1];

        /* if either adjacent frame is voiced, make this one voiced */

        unpacked_bits[2] = (v1 || v3);

        return 0;

        break;

    case CODEC2_MODE_1400:

        v3 = unpacked_bits[1+1+8+1];

        /* if either adjacent frame is voiced, make this one voiced */

        unpacked_bits[10] = (v1 || v3);

        return 0;

        break;

    case CODEC2_MODE_1600:
        v3 = unpacked_bits[1+1+8+5+1];

        /* if either adjacent frame is voiced, make this one voiced */

        unpacked_bits[15] = (v1 || v3);

        return 0;

        break;
    }

    return -1;
}

void codec2_set_natural_or_gray(struct CODEC2 *c2, int gray)
{
    assert(c2 != NULL);
    c2->gray = gray;
}

void codec2_set_softdec(struct CODEC2 *c2, float *softdec)
{
    assert(c2 != NULL);
    c2->softdec = softdec;
}

