/*---------------------------------------------------------------------------*\

  FILE........: c2enc.c
  AUTHOR......: David Rowe
  DATE CREATED: 23/8/2010

  Encodes a file of raw speech samples using codec2 and outputs a file
  of bits.

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

#include "codec2.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int main(int argc, char *argv[])
{
    int            mode;
    void          *codec2;
    FILE          *fin;
    FILE          *fout;
    short         *buf;
    unsigned char *bits;
    int            nsam, nbit, nbyte, gray, softdec;
    float         *unpacked_bits;
    int            bit, byte,i;

    if (argc < 4) {
	printf("usage: c2enc 3200|2400|1600|1400|1300|1200|700|700B InputRawspeechFile OutputBitFile [--natural] [--softdec]\n");
	printf("e.g    c2enc 1400 ../raw/hts1a.raw hts1a.c2\n");
	printf("e.g    c2enc 1300 ../raw/hts1a.raw hts1a.c2 --natural\n");
	exit(1);
    }

    if (strcmp(argv[1],"3200") == 0)
	mode = CODEC2_MODE_3200;
    else if (strcmp(argv[1],"2400") == 0)
	mode = CODEC2_MODE_2400;
    else if (strcmp(argv[1],"1600") == 0)
	mode = CODEC2_MODE_1600;
    else if (strcmp(argv[1],"1400") == 0)
	mode = CODEC2_MODE_1400;
    else if (strcmp(argv[1],"1300") == 0)
	mode = CODEC2_MODE_1300;
    else if (strcmp(argv[1],"1200") == 0)
	mode = CODEC2_MODE_1200;
    else if (strcmp(argv[1],"700") == 0)
	mode = CODEC2_MODE_700;
    else if (strcmp(argv[1],"700B") == 0)
	mode = CODEC2_MODE_700B;
    else {
	fprintf(stderr, "Error in mode: %s.  Must be 3200, 2400, 1600, 1400, 1300, 1200, 700 or 700B\n", argv[1]);
	exit(1);
    }

    if (strcmp(argv[2], "-")  == 0) fin = stdin;
    else if ( (fin = fopen(argv[2],"rb")) == NULL ) {
	fprintf(stderr, "Error opening input speech file: %s: %s.\n",
         argv[2], strerror(errno));
	exit(1);
    }

    if (strcmp(argv[3], "-") == 0) fout = stdout;
    else if ( (fout = fopen(argv[3],"wb")) == NULL ) {
	fprintf(stderr, "Error opening output compressed bit file: %s: %s.\n",
         argv[3], strerror(errno));
	exit(1);
    }

    codec2 = codec2_create(mode);
    nsam = codec2_samples_per_frame(codec2);
    nbit = codec2_bits_per_frame(codec2);
    buf = (short*)malloc(nsam*sizeof(short));
    nbyte = (nbit + 7) / 8;

    bits = (unsigned char*)malloc(nbyte*sizeof(char));
    unpacked_bits = (float*)malloc(nbit*sizeof(float));

    gray = 1;
    softdec = 0;
    for (i=4; i<argc; i++) {
        if (strcmp(argv[i], "--natural") == 0) {
            gray = 0;
        }
        if (strcmp(argv[i], "--softdec") == 0) {
            softdec = 1;
        }
    }
    codec2_set_natural_or_gray(codec2, gray);
    //fprintf(stderr,"gray: %d softdec: %d\n", gray, softdec);

    while(fread(buf, sizeof(short), nsam, fin) == (size_t)nsam) {

	codec2_encode(codec2, bits, buf);

	if (softdec) {
            /* unpack bits, MSB first, send as soft decision float */

            bit = 7; byte = 0;
            for(i=0; i<nbit; i++) {
                unpacked_bits[i] = 1.0 - 2.0*((bits[byte] >> bit) & 0x1);
                bit--;
                if (bit < 0) {
                    bit = 7;
                    byte++;
                }
            }
            fwrite(unpacked_bits, sizeof(float), nbit, fout);
        }
        else
            fwrite(bits, sizeof(char), nbyte, fout);

	// if this is in a pipeline, we probably don't want the usual
        // buffering to occur

        if (fout == stdout) fflush(stdout);
        if (fin == stdin) fflush(stdin);
    }

    codec2_destroy(codec2);

    free(buf);
    free(bits);
    free(unpacked_bits);
    fclose(fin);
    fclose(fout);

    return 0;
}
