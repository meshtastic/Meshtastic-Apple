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

#define FSK_FRAME_SIZE 100
#define INIT_SEQ {0,1,1,0,1,0,0,1,1,1,1,0,1,1,0,0,0,0,1,0,1,1,0,1,0,1,0,1,0,0,1,1}

uint8_t init[] = INIT_SEQ;
uint8_t finit[sizeof(init)];

int find_init(uint8_t next){
	memmove(&finit[0],&finit[1],sizeof(init)-1);
	finit[sizeof(init)-1] = next;
	int i, err = 0;
	for(i = 0;i<sizeof(init); i++){
		if(init[i]!=finit[i]) err++;
	}
	return err<=3;
}

int main(int argc,char *argv[]){
    int bitcnt,bitcorr;
    FILE *fin;
    uint8_t bitbuf,cntbit;;
    
    /* Seed the RNG with some constant */
    srand(158324);
    
    if(argc != 2){
        fprintf(stderr,"usage: %s InputBitsOnePerByte \n",argv[0]);
        exit(1);
    }
    
	
	if(strcmp(argv[1],"-")==0 || argc<2){
		fin = stdin;
	}else{
		fin = fopen(argv[1],"r");
	}
    
    if(fin==NULL){
        fprintf(stderr,"Couldn't open test vector files\n");
        goto cleanup;
    }
    bitcnt = 0;
    bitcorr = 0;
    
    /* Find frame start word */
    do{
		fread(&bitbuf,sizeof(uint8_t),1,fin);
	}while(!find_init(bitbuf));
	
	
    while(fread(&bitbuf,sizeof(uint8_t),1,fin)>0){
		cntbit = rand()&0x1;
		if( (cntbit>0)==(bitbuf>0))
			bitcorr++;
		bitcnt++;
		if(fin == stdin)
			fflush(fin);
	}
	fprintf(stderr,"FSK BER %f, bits tested %d, bit errors %d\n",1-((float)bitcorr/(float)bitcnt),bitcnt,bitcnt-bitcorr);
    
    cleanup:
    fclose(fin);
}
