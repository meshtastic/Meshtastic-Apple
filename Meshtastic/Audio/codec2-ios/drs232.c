/*---------------------------------------------------------------------------*\

  FILE........: drs232.c
  AUTHOR......: David Rowe
  DATE CREATED: March 2016

  Looks for a unique word in series of bits.  When found, deframes a RS232
  encoded frame of bytes.  Used for high biit rate Horus SSTV reception.

  Frame format:

    16 bytes 0x55 - 0xabcd UW - 256 bytes of payload - 2 bytes CRC

  Each byte is encoded as a 10 bit RS232 serial word: 
  
    0 LSB .... MSB 1

  Building:
   
    $ gcc drs232.c -o drs232.c -Wall

\*---------------------------------------------------------------------------*/


/*
  Copyright (C) 2016 David Rowe

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
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* states -----------------------------------------------*/

#define LOOK_FOR_UW    0
#define COLLECT_PACKET 1

/* packet parameters */

#define UW_BYTES               2
#define UW_BITS                20
#define BYTES_PER_PACKET       256
#define CRC_BYTES              2
#define BITS_PER_BYTE          10
#define UNPACKED_PACKET_BYTES  ((UW_BYTES+BYTES_PER_PACKET+CRC_BYTES)*BITS_PER_BYTE)

/* UW pattern we look for, inclduing start/stop bits */

uint8_t uw[] = {
    /* 0xb                0xa */
    0, 1, 1, 0, 1, 0, 1, 0, 1, 1,
    /* 0xd                0xc */
    0, 1, 0, 1, 1, 0, 0, 1, 1, 1,
};

 // from http://stackoverflow.com/questions/10564491/function-to-calculate-a-crc16-checksum

unsigned short gen_crc16(unsigned char* data_p, int length){
    unsigned char x;
    unsigned short crc = 0xFFFF;

    while (length--){
        x = crc >> 8 ^ *data_p++;
        x ^= x>>4;
        crc = (crc << 8) ^ ((unsigned short)(x << 12)) ^ ((unsigned short)(x <<5)) ^ ((unsigned short)x);
    }
    
    return crc;
}


int main(int argc, char *argv[]) {
    FILE       *fin, *fout;
    int         state, next_state, i, j, k, ind, score, bits_read;
    char        bit;
    uint8_t     unpacked_packet[UNPACKED_PACKET_BYTES];
    uint8_t     packet[BYTES_PER_PACKET+CRC_BYTES];
    uint8_t     abyte;
    uint16_t    tx_checksum, rx_checksum;

    if (argc < 3) {
	printf("usage: drs232 InputOneBitPerChar OutputPackets\n");
	exit(1);
    }

    if (strcmp(argv[1], "-")  == 0) fin = stdin;
    else if ( (fin = fopen(argv[1],"rb")) == NULL ) {
	fprintf(stderr, "Error opening input speech file: %s: %s.\n",
         argv[2], strerror(errno));
	exit(1);
    }

    if (strcmp(argv[2], "-") == 0) fout = stdout;
    else if ( (fout = fopen(argv[2],"wb")) == NULL ) {
	fprintf(stderr, "Error opening output speech file: %s: %s.\n",
         argv[3], strerror(errno));
	exit(1);
    }

    state = LOOK_FOR_UW;
    for(i=0; i<UNPACKED_PACKET_BYTES; i++)
        unpacked_packet[i] = 0;
    bits_read = 0;

    while(fread(&bit, sizeof(char), 1, fin) == 1) {
        bits_read++;
        if (state == LOOK_FOR_UW) {

            /* put latest input bit into sliding buffer */
            
            for(i=0; i<UW_BITS-1; i++) {
                unpacked_packet[i] = unpacked_packet[i+1];
            }
            unpacked_packet[i] = bit;

            /* lets see if it matches the UW */

            score = 0;
            for(i=0; i<UW_BITS; i++) {
                score += (unpacked_packet[i] == uw[i]);
                /* if (i == BITS_PER_BYTE)
                    printf(" ");
                    printf("%1d", unpacked_packet[i]); */
            }
            //printf("\n");
            
            //fprintf(stderr,"UW score: %d\n", score);
            if (score == UW_BITS) {
                fprintf(stderr,"UW found!\n");
                ind = UW_BITS;
                next_state = COLLECT_PACKET;
            }             
        }

        if (state == COLLECT_PACKET) {
            unpacked_packet[ind++] = bit;
 
           if (ind == UNPACKED_PACKET_BYTES) {

               /* OK we have enough bits, remove RS232 sync bits and pack */

               for(i=UW_BITS,k=0; i<UNPACKED_PACKET_BYTES; i+=BITS_PER_BYTE,k++) {
                   //for(j=0; j<BITS_PER_BYTE; j++)
                   //    printf("%1d", unpacked_packet[i+j]);
                   //printf("\n");
                   abyte = 0;
                   for(j=0; j<8; j++) {
                       abyte |= unpacked_packet[i+j+1] << j;
                   }
                   packet[k] = abyte;
                   //printf("k:%d 0x%02x\n", k, packet[k]);
                   //if (k == 4)
                   //  exit(0);
               }

               /* output if CRC check is OK */

               rx_checksum = gen_crc16(packet, BYTES_PER_PACKET);
               tx_checksum = packet[BYTES_PER_PACKET] + (packet[BYTES_PER_PACKET+1] << 8);

               fprintf(stderr, "k=%d bytes after UW  tx_checksum: 0x%02x rx_checksum: 0x%02x\n", k, tx_checksum, rx_checksum);

               if (rx_checksum == tx_checksum) {
                   fwrite(packet, sizeof(char), BYTES_PER_PACKET, fout);
               }

               next_state = LOOK_FOR_UW;
            }

        }
        //if (bits_read == (16*10 + UNPACKED_PACKET_BYTES))
        //    exit(0);

        state = next_state;      
    }

    fclose(fin);
    fclose(fout);

    return 0;
}
