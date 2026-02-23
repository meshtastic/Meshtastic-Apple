/*---------------------------------------------------------------------------*\

  FILE........: fsk_get_test_bits.c
  AUTHOR......: Brady O'Brien
  DATE CREATED: Januar 2016

  Generates a pseudorandom sequence of bits for testing of fsk_mod and fsk_demod

\*---------------------------------------------------------------------------*/


/*
  Copyright (C) 2016 David Rowe

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


#include <stdio.h>
#include <string.h>
#include "fsk.h"
#include "codec2_fdmdv.h"

#define FSK_FRAME_SIZE 400
#define INIT_SEQ {0,1,1,0,1,0,0,1,1,1,1,0,1,1,0,0,0,0,1,0,1,1,0,1,0,1,0,1,0,0,1,1}

uint8_t init[] = INIT_SEQ;

int main(int argc,char *argv[]){
    int bitcnt;
    int i,j;
    FILE *fout;
    uint8_t *bitbuf;
    
    
    if(argc != 3){
        fprintf(stderr,"usage: %s OutputBitsOnePerByte FrameCount\n",argv[0]);
        exit(1);
    }
    
    /* Extract parameters */
    bitcnt = atoi(argv[2]);
	
	if(strcmp(argv[1],"-")==0){
		fout = stdout;
	}else{
		fout = fopen(argv[1],"w");
	}
    
    if(fout==NULL){
        fprintf(stderr,"Couldn't open test vector files\n");
        goto cleanup;
    }
    
    /* allocate buffers for processing */
    bitbuf = (uint8_t*)alloca(sizeof(uint8_t)*FSK_FRAME_SIZE);
    
    /* Write out sync frame and sequence */
    for(i=0; i<FSK_FRAME_SIZE; i){
	bitbuf[i++] = rand()&0x1;
    }
    for(i=0;i<sizeof(init);i++){
	bitbuf[FSK_FRAME_SIZE-sizeof(init)+i]=init[i];
    }
    fwrite(bitbuf,sizeof(uint8_t),FSK_FRAME_SIZE,fout);
    
    
    /* Seed the RNG with some constant */
    srand(158324);
    for(i=0; i<bitcnt; i++){
	for(j=0; j<FSK_FRAME_SIZE; j++){
		bitbuf[j] = rand()&0x1;
	}
	fwrite(bitbuf,sizeof(uint8_t),FSK_FRAME_SIZE,fout);
	if(fout == stdout){
	    fflush(fout);
	}
    }
    
    cleanup:
    fclose(fout);
}
