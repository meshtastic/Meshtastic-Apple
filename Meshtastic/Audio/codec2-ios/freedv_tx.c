/*---------------------------------------------------------------------------*\

  FILE........: freedv_tx.c
  AUTHOR......: David Rowe
  DATE CREATED: August 2014

  Demo transmit program for FreeDV API functions.

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2014 David Rowe

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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#include "freedv_api.h"
#include "codec2.h"

struct my_callback_state {
    char  tx_str[80];
    char *ptx_str;
    int calls;
};

char my_get_next_tx_char(void *callback_state) {
    struct my_callback_state* pstate = (struct my_callback_state*)callback_state;
    char  c = *pstate->ptx_str++;

    if (*pstate->ptx_str == 0) {
        pstate->ptx_str = pstate->tx_str;
    }

    return c;
}

void my_get_next_proto(void *callback_state,char *proto_bits){
    struct my_callback_state* cb_states = (struct my_callback_state*)(callback_state);
    snprintf(proto_bits,3,"%2d",cb_states->calls);
    cb_states->calls = cb_states->calls + 1;
}

/* Called when a packet has been received */
void my_datarx(void *callback_state, unsigned char *packet, size_t size) {
    /* This should not happen while sending... */
    fprintf(stderr, "datarx callback called, this should not happen!\n");    
}

/* Called when a new packet can be send */
void my_datatx(void *callback_state, unsigned char *packet, size_t *size) {
    static int data_toggle;
    
    /* Data could come from a network interface, here we just make up some */
    
    data_toggle = !data_toggle;
    if (data_toggle) {
        /* Send a packet with data */
        int i;
	for (i = 0; i < 64; i++)
	    packet[i] = i;
	*size = i;
    } else {
        /* set size to zero, the freedv api will insert a header frame */
        *size = 0;
    }
}


int main(int argc, char *argv[]) {
    FILE                     *fin, *fout;
    short                    *speech_in;
    short                    *mod_out;
    struct freedv            *freedv;
    struct my_callback_state  my_cb_state;
    int                       mode;
    int                       n_speech_samples;
    int                       n_nom_modem_samples;
    int                       use_codectx;
    int                       use_datatx;
    struct CODEC2             *c2;
    int                       i;

    if (argc < 4) {
        printf("usage: %s 1600|700|700B|2400A|2400B|800XA InputRawSpeechFile OutputModemRawFile [--testframes] [--codectx] [--datatx]\n", argv[0]);
        printf("e.g    %s 1600 hts1a.raw hts1a_fdmdv.raw\n", argv[0]);
        exit(1);
    }

    mode = -1;
    if (!strcmp(argv[1],"1600"))
        mode = FREEDV_MODE_1600;
    if (!strcmp(argv[1],"700"))
        mode = FREEDV_MODE_700;
    if (!strcmp(argv[1],"700B"))
        mode = FREEDV_MODE_700B;
    if (!strcmp(argv[1],"2400A"))
        mode = FREEDV_MODE_2400A;
    if (!strcmp(argv[1],"2400B"))
        mode = FREEDV_MODE_2400B;
    if (!strcmp(argv[1],"800XA"))
        mode = FREEDV_MODE_800XA;
    assert(mode != -1);

    if (strcmp(argv[2], "-")  == 0) fin = stdin;
    else if ( (fin = fopen(argv[2],"rb")) == NULL ) {
        fprintf(stderr, "Error opening input raw speech sample file: %s: %s.\n", argv[2], strerror(errno));
        exit(1);
    }

    if (strcmp(argv[3], "-") == 0) fout = stdout;
    else if ( (fout = fopen(argv[3],"wb")) == NULL ) {
        fprintf(stderr, "Error opening output modem sample file: %s: %s.\n", argv[3], strerror(errno));
        exit(1);
    }

    freedv = freedv_open(mode);
    assert(freedv != NULL);

    use_codectx = 0;
    use_datatx = 0;

    if (argc > 4) {
        for (i = 4; i < argc; i++) {
            if (strcmp(argv[i], "--testframes") == 0) {
                freedv_set_test_frames(freedv, 1);
            }
            if (strcmp(argv[i], "--codectx") == 0) {
                int c2_mode;

                if (mode == FREEDV_MODE_700)  {
		    c2_mode = CODEC2_MODE_700;
		} else if ((mode == FREEDV_MODE_700B)|| (mode == FREEDV_MODE_800XA)) {
                    c2_mode = CODEC2_MODE_700B;
                } else {
                    c2_mode = CODEC2_MODE_1300;
                }
                use_codectx = 1;

                c2 = codec2_create(c2_mode);
                assert(c2 != NULL);
            }
	    if (strcmp(argv[i], "--datatx") == 0) {
	        unsigned char header[6] = { 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc };
	        freedv_set_data_header(freedv, header);
		use_datatx = 1;
	    }
        }
    }
    freedv_set_snr_squelch_thresh(freedv, -100.0);
    freedv_set_squelch_en(freedv, 1);

    n_speech_samples = freedv_get_n_speech_samples(freedv);
    n_nom_modem_samples = freedv_get_n_nom_modem_samples(freedv);
    speech_in = (short*)malloc(sizeof(short)*n_speech_samples);
    assert(speech_in != NULL);
    mod_out = (short*)malloc(sizeof(short)*n_nom_modem_samples);
    assert(mod_out != NULL);

    /* set up callback for txt msg chars */

    sprintf(my_cb_state.tx_str, "cq cq cq hello world\r");
    my_cb_state.ptx_str = my_cb_state.tx_str;
    my_cb_state.calls = 0;
    freedv_set_callback_txt(freedv, NULL, &my_get_next_tx_char, &my_cb_state);
    
    /* set up callback for protocol bits */
    freedv_set_callback_protocol(freedv, NULL, &my_get_next_proto, &my_cb_state);

    /* set up callback for data packets */
    freedv_set_callback_data(freedv, my_datarx, my_datatx, &my_cb_state);

    /* OK main loop */

    while(fread(speech_in, sizeof(short), n_speech_samples, fin) == n_speech_samples) {
        if (use_codectx == 0) {
            /* Use the freedv_api to do everything: speech encoding, modulating */
            freedv_tx(freedv, mod_out, speech_in);
        } else {
            int bits_per_codec_frame = codec2_bits_per_frame(c2);
            int bytes_per_codec_frame = (bits_per_codec_frame + 7) / 8;
            int codec_frames = freedv_get_n_codec_bits(freedv) / bits_per_codec_frame;
            int samples_per_frame = codec2_samples_per_frame(c2);
            unsigned char encoded[bytes_per_codec_frame * codec_frames];
            unsigned char *enc_frame = encoded;
            short *speech_frame = speech_in;
	    float energy = 0;

            /* Encode the speech ourself (or get it from elsewhere, e.g. network) */
            for (i = 0; i < codec_frames; i++) {
                codec2_encode(c2, enc_frame, speech_frame);
                energy += codec2_get_energy(c2, enc_frame);
	        enc_frame += bytes_per_codec_frame;
                speech_frame += samples_per_frame;
	    }
	    energy /= codec_frames;
	    
	    /* Is the audio fragment quiet? */
	    if (use_datatx && energy < 1.0) {
                /* Insert a frame with data instead of speech */
		freedv_datatx(freedv, mod_out);
            } else {
                /* Use the freedv_api to modulate already encoded frames */
                freedv_codectx(freedv, mod_out, encoded);
            }
	}

        fwrite(mod_out, sizeof(short), n_nom_modem_samples, fout);

	/* if this is in a pipeline, we probably don't want the usual
           buffering to occur */

        if (fout == stdout) fflush(stdout);
        if (fin == stdin) fflush(stdin);
    }

    free(speech_in);
    free(mod_out);
    freedv_close(freedv);
    fclose(fin);
    fclose(fout);

    return 0;
}

