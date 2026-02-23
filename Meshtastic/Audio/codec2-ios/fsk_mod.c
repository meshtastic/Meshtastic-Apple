/*---------------------------------------------------------------------------*\

  FILE........: fsk_mod.c
  AUTHOR......: Brady O'Brien
  DATE CREATED: 8 January 2016

  C test driver for fsk_mod in fsk.c. Reads in a set of bits to modulate
   from a file, passed as a parameter, and writes modulated output to
   another file
   

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

#include <stdio.h>
#include <string.h>
#include "fsk.h"
#include "codec2_fdmdv.h"

int main(int argc,char *argv[]){
    struct FSK *fsk;
    int Fs,Rs,f1,fs,M;
    int i;
    int p;
    FILE *fin,*fout;
    uint8_t *bitbuf;
    int16_t *rawbuf;
    float *modbuf;
    
    if(argc<8){
        fprintf(stderr,"usage: %s Mode SampleFreq SymbolFreq TxFreq1 TxFreqSpace InputOneBitPerCharFile OutputModRawFile\n",argv[0]);
        exit(1);
    }
    
    /* Extract parameters */
    M = atoi(argv[1]);
    Fs = atoi(argv[2]);
    Rs = atoi(argv[3]);
    f1 = atoi(argv[4]);
    fs = atoi(argv[5]);
    
    if(strcmp(argv[6],"-")==0){
		fin = stdin;
	}else{
		fin = fopen(argv[6],"r");
	}
	
	if(strcmp(argv[7],"-")==0){
		fout = stdout;
	}else{
		fout = fopen(argv[7],"w");
	}
    
    p = Fs/Rs;
    
    /* set up FSK */
    fsk = fsk_create_hbr(Fs,Rs,p,M,f1,fs);
    
    if(fin==NULL || fout==NULL || fsk==NULL){
        fprintf(stderr,"Couldn't open test vector files\n");
        goto cleanup;
    }
    
    /* allocate buffers for processing */
    bitbuf = (uint8_t*)malloc(sizeof(uint8_t)*fsk->Nbits);
    rawbuf = (int16_t*)malloc(sizeof(int16_t)*fsk->N);
    modbuf = (float*)malloc(sizeof(float)*fsk->N);
    
    /* Modulate! */
    while( fread(bitbuf,sizeof(uint8_t),fsk->Nbits,fin) == fsk->Nbits ){
        fsk_mod(fsk,modbuf,bitbuf);
        for(i=0; i<fsk->N; i++){
			rawbuf[i] = (int16_t)(modbuf[i]*(float)FDMDV_SCALE);
		}
        fwrite(rawbuf,sizeof(int16_t),fsk->N,fout);
        
		if(fin == stdin || fout == stdin){
			fflush(fin);
			fflush(fout);
		}
    }
    free(bitbuf);
    free(rawbuf);
    free(modbuf);
    
    cleanup:
    fclose(fin);
    fclose(fout);
    fsk_destroy(fsk);
    exit(0);
}
